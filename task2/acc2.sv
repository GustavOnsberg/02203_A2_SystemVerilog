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
    localparam int LAST_ROW      = 287;
    localparam int LAST_WORD     = 87;
 
    typedef enum logic [2:0] {IDLE, FILL, RD, SHIFT, CALC, WR, DONE} state_t;
    state_t state;
 
    // counters
    logic [8:0]        i;        // row, 0..287
    logic signed [7:0] k;        // word in row, -1..87 (-1 = preload step)
    logic              c;        // read phase: 0 = issue address, 1 = data arrives
    logic [6:0]        n;        // prefill counter, 0..WORDS_PER_ROW
 
    // boundary conditions: pixels outside the image copy the nearest edge pixel
    logic first_row, last_row;
    assign first_row = (i == 9'd0);
    assign last_row  = (i == 9'(LAST_ROW));
 
    // window: [row][0=L, 1=C, 2=R], row 0 = i-1, row 1 = i, row 2 = i+1
    logic [31:0] win [0:2][0:2];
    logic [31:0] newcol [0:2];
    logic [31:0] outreg;
 
    // ---------------------------------------------------------------
    // Line buffers: the two previous image rows, so that only row i+1
    // has to be read from RAM. No reset, so they can map to LUT RAM.
    // ---------------------------------------------------------------
    logic [31:0] lb0 [0:WORDS_PER_ROW-1];   // row i-1
    logic [31:0] lb1 [0:WORDS_PER_ROW-1];   // row i

    logic [6:0]  lb_col;                    // column word k+1
    logic [31:0] lb0_q, lb1_q;              // asynchronous read data
    logic [31:0] below;                     // word of row i+1
    logic        lb_we;                     // both buffers are written together
    logic [6:0]  lb_waddr;
    logic [31:0] lb0_wdata;

    assign lb_col    = 7'(k + 8'sd1);
    assign lb0_q     = lb0[lb_col];
    assign lb1_q     = lb1[lb_col];
    // there is no row below the last row: copy row i instead
    assign below     = last_row ? lb1_q : dataR;

    // prefill: word n-1 of row 0 arrives while address n is issued, and goes
    // into both buffers because row 0 is also the row "above" row 0.
    // Afterwards: move column lb_col down one row.
    assign lb_we     = (state == FILL && n != 7'd0) ||
                       (state == RD && c && k != LAST_WORD);
    assign lb_waddr  = (state == FILL) ? 7'(n - 7'd1) : lb_col;
    assign lb0_wdata = (state == FILL) ? dataR : lb1_q;

    always_ff @(posedge clk) begin
        if (lb_we) begin
            lb0[lb_waddr] <= lb0_wdata;
            lb1[lb_waddr] <= below;         // in FILL: i = 0, so below = dataR
        end
    end

    // ---------------------------------------------------------------
    // Datapath: pixel extraction and Sobel (combinational)
    // ---------------------------------------------------------------
    logic [7:0] px [0:2][0:5];   // per row: L[3], C[0..3], R[0]
 
    always_comb begin
        for (int r = 0; r < 3; r++) begin
            // memory is little-endian: pixel p of a word is in bits [8p +: 8]
            // L[3] = last pixel of previous word; left image edge copies C[0]
            px[r][0] = (k == 8'sd0) ? win[r][1][7:0] : win[r][0][31:24];
            px[r][1] = win[r][1][7:0];      // C[0]
            px[r][2] = win[r][1][15:8];     // C[1]
            px[r][3] = win[r][1][23:16];    // C[2]
            px[r][4] = win[r][1][31:24];    // C[3]
            // R[0] = first pixel of next word; right image edge copies C[3]
            px[r][5] = (k == LAST_WORD) ? win[r][1][31:24] : win[r][2][7:0];
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
        rd_row = 16'(i) + 16'd1;                // only row i+1 is read
        col    = 16'(k + 8'sd1);                // column word k+1 (0..88)
 
        en     = 1'b0;
        we     = 1'b0;
        addr   = '0;
        dataW  = outreg;
        finish = 1'b0;
 
        case (state)
            FILL: if (n != 7'(WORDS_PER_ROW)) begin  // row 0 = words 0..87
                    en   = 1'b1;
                    addr = 16'(n);
                end
            RD: if (!c && k != LAST_WORD && !last_row) begin
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
            i      <= 9'd0;
            k      <= -8'sd1;
            c      <= 1'b0;
            n      <= '0;
            outreg <= '0;
            clear_window();
        end else begin
            case (state)
                IDLE: if (start) begin
                    i     <= 9'd0;
                    k     <= -8'sd1;
                    c     <= 1'b0;
                    n     <= '0;
                    state <= FILL;
                end
 
                FILL: begin
                    if (n != 7'(WORDS_PER_ROW))
                        n <= n + 7'd1;
                    else                             // last word is being stored
                        state <= RD;
                end
 
                RD: begin
                    if (k == LAST_WORD) begin
                        // no word 88 in a row: skip the read (right edge is mirrored)
                        state <= SHIFT;
                    end else if (!c) begin
                        c <= 1'b1;
                    end else begin
                        // data of the address issued in the previous cycle arrives now
                        newcol[0] <= first_row ? lb1_q : lb0_q;  // row i-1
                        newcol[1] <= lb1_q;          // row i
                        newcol[2] <= below;                      // row i+1
                        c         <= 1'b0;
                        state     <= SHIFT;
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
                        state <= RD;
                    end else if (!last_row) begin
                        i     <= i + 9'd1;
                        k     <= -8'sd1;
                        state <= RD;
                    end else
                        state <= DONE;
                end
 
                DONE: if (!start) state <= IDLE;
 
                default: state <= IDLE;
            endcase
        end
    end
 
endmodule
