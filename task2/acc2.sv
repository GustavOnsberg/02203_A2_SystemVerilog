// -----------------------------------------------------------------------------
//
//  Title      :  Edge-Detection design project - task 2.
//             :
//  Developers :  YOUR NAME HERE - s??????@student.dtu.dk
//             :  YOUR NAME HERE - s??????@student.dtu.dk
//             :
//  Purpose    :  This design contains an entity for the accelerator that must be build
//             :  in task two of the Edge Detection design project. It contains an
//             :  architecture skeleton for the entity as well.
//             :
//  Revision   :  1.0   ??-??-??     Final version
//             :
//
// ----------------------------------------------------------------------------//

//------------------------------------------------------------------------------
// The module for task two. Notice the additional signals for the memory.
// reset is active high.
//------------------------------------------------------------------------------


module acc (
    input  logic        clk,
    input  logic        reset,    // assumed active high, synchronous
    input  logic        start,
    output logic        finish,
    output logic [15:0] addr,
    input  logic [31:0] dataR,
    output logic [31:0] dataW,
    output logic        en,
    output logic        we
);
 
    localparam int WORDS_PER_ROW = 88;                 // 352 / 4
    localparam int DST_BASE      = 25344;              // 88 * 288, start of processed image
    localparam int LAST_ROW      = 286;
    localparam int LAST_WORD     = 87;
    localparam int LAST_BORDER_ROW = 287;              // bottom border row (written as zeros)
 
    typedef enum logic [2:0] {IDLE, RD, SHIFT, CALC, WR, DONE} state_t;
    state_t state;
 
    // counters
    logic [8:0]        i;        // row, 1..286
    logic signed [7:0] k;        // word in row, -1..87 (-1 = preload step)
    logic [1:0]        c;        // read phase 0..3
 
    // rows 0 and 287 are not computed, only written as zeros
    logic is_border;
    assign is_border = (i == 9'd0) || (i == 9'(LAST_BORDER_ROW));
 
    // window: [row][0=L, 1=C, 2=R], row 0 = i-1, row 1 = i, row 2 = i+1
    logic [31:0] win [0:2][0:2];
    logic [31:0] newcol [0:2];
    logic [31:0] outreg;
 
    // ---------------------------------------------------------------
    // Datapath: pixel extraction and Sobel (combinational)
    // ---------------------------------------------------------------
    logic [7:0] px [0:2][0:5];   // per row: L[3], C[0..3], R[0]
 
    always_comb begin
        for (int r = 0; r < 3; r++) begin
            // memory is little-endian: pixel p of a word is in bits [8p +: 8]
            px[r][0] = win[r][0][31:24];    // L[3] (last pixel of previous word)
            px[r][1] = win[r][1][7:0];      // C[0]
            px[r][2] = win[r][1][15:8];     // C[1]
            px[r][3] = win[r][1][23:16];    // C[2]
            px[r][4] = win[r][1][31:24];    // C[3]
            px[r][5] = win[r][2][7:0];      // R[0] (first pixel of next word)
        end
    end
 
    function automatic logic [7:0] sobel(
        input logic [7:0] s11, s12, s13,
        input logic [7:0] s21,      s23,
        input logic [7:0] s31, s32, s33
    );
        logic signed [11:0] dx, dy;
        logic        [11:0] mag;
        begin
            dx = $signed({4'b0, s13}) - $signed({4'b0, s11})
               + 2 * ($signed({4'b0, s23}) - $signed({4'b0, s21}))
               + $signed({4'b0, s33}) - $signed({4'b0, s31});
            dy = $signed({4'b0, s11}) - $signed({4'b0, s31})
               + 2 * ($signed({4'b0, s12}) - $signed({4'b0, s32}))
               + $signed({4'b0, s13}) - $signed({4'b0, s33});
            mag = (dx[11] ? -dx : dx) + (dy[11] ? -dy : dy);   // |Dx| + |Dy|, max 2040
            sobel = (mag > 255) ? 8'd255 : mag[7:0];           // saturate
        end
    endfunction
 
    logic [31:0] result;
    always_comb begin
        for (int j = 0; j < 4; j++) begin
            // output pixel j uses px[.][j], px[.][j+1], px[.][j+2]
            result[8*j +: 8] = sobel(px[0][j], px[0][j+1], px[0][j+2],
                                          px[1][j],             px[1][j+2],
                                          px[2][j], px[2][j+1], px[2][j+2]);
        end
    end
 
    // ---------------------------------------------------------------
    // Outputs (combinational from state and counters)
    // ---------------------------------------------------------------
    logic [15:0] rd_row, col;
 
    always_comb begin
        rd_row = 16'(i) - 16'd1 + 16'(c);       // row i-1+c
        col    = 16'(k + 8'sd1);                // column word k+1 (0..88)
 
        en     = 1'b0;
        we     = 1'b0;
        addr   = '0;
        dataW  = outreg;
        finish = 1'b0;
 
        case (state)
            RD: if (c != 2'd3 && k != LAST_WORD) begin
                    en   = 1'b1;
                    we   = 1'b0;
                    addr = rd_row * WORDS_PER_ROW + col;
                end
            WR: begin
                    en   = 1'b1;
                    we   = 1'b1;
                    addr = DST_BASE + 16'(i) * WORDS_PER_ROW + 16'(k);
                end
            DONE: finish = 1'b1;
            default: ;
        endcase
    end
 
    // ---------------------------------------------------------------
    // Control + register updates
    // ---------------------------------------------------------------
    task automatic clear_window();
        for (int r = 0; r < 3; r++)
            for (int w = 0; w < 3; w++)
                win[r][w] <= '0;
    endtask
 
    always_ff @(posedge clk) begin
        if (reset) begin
            state  <= IDLE;
            i      <= 9'd1;
            k      <= -8'sd1;
            c      <= 2'd0;
            outreg <= '0;
            clear_window();
        end else begin
            case (state)
                IDLE: if (start) begin
                    i      <= 9'd0;          // row 0 = top border: write zeros
                    k      <= 8'sd0;
                    c      <= 2'd0;
                    outreg <= '0;
                    clear_window();
                    state  <= WR;
                end
 
                RD: begin
                    if (k == LAST_WORD) begin
                        // no word 88 in a row: zero-fill, skip the reads
                        for (int r = 0; r < 3; r++) newcol[r] <= '0;
                        c     <= 2'd0;
                        state <= SHIFT;
                    end else begin
                        // data of the address issued in the previous cycle arrives now
                        if (c == 2'd1) newcol[0] <= dataR;
                        if (c == 2'd2) newcol[1] <= dataR;
                        if (c == 2'd3) newcol[2] <= dataR;
                        if (c == 2'd3) begin
                            c     <= 2'd0;
                            state <= SHIFT;
                        end else
                            c <= c + 2'd1;
                    end
                end
 
                SHIFT: begin
                    for (int r = 0; r < 3; r++) begin
                        win[r][0] <= win[r][1];   // L <= C
                        win[r][1] <= win[r][2];   // C <= R
                        win[r][2] <= newcol[r];   // R <= new column
                    end
                    if (k == -8'sd1) begin        // preload step: no output yet
                        k     <= 8'sd0;
                        state <= RD;
                    end else
                        state <= CALC;
                end
 
                CALC: begin
                    outreg <= result;
                    state  <= WR;
                end
 
                WR: begin
                    if (k != LAST_WORD) begin
                        k     <= k + 8'sd1;
                        state <= is_border ? WR : RD;   // border rows: keep writing zeros
                    end else if (i != LAST_BORDER_ROW) begin
                        i <= i + 9'd1;
                        if (i == LAST_ROW) begin        // next row is the bottom border
                            k      <= 8'sd0;
                            outreg <= '0;
                            state  <= WR;
                        end else begin                  // next row is a normal row
                            k      <= -8'sd1;
                            clear_window();
                            state  <= RD;
                        end
                    end else
                        state <= DONE;
                end
 
                DONE: if (!start) state <= IDLE;
 
                default: state <= IDLE;
            endcase
        end
    end
 
endmodule
