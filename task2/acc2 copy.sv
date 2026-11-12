// -----------------------------------------------------------------------------
//
//  Title      :  Edge-Detection design project - task 2.
//             :
//  Developers :  YOUR NAME HERE - s??????@student.dtu.dk
//             :  YOUR NAME HERE - s??????@student.dtu.dk
//             :
//  Purpose    :  Sobel edge-detection accelerator (FSMD, Moore outputs).
//             :
//             :  Processes the image one 32-bit word (4 pixels) at a time.
//             :  A 3x3-word window (rows i-1, i, i+1  x  words k-1, k, k+1)
//             :  is kept in registers. For every output word, only the three
//             :  words of the new window column are read from the RAM (one per
//             :  row); the other six are shifted in from the previous step.
//             :
//             :  Boundary conditions are ignored (task 1): the first/last
//             :  image row is not processed, and the first/last pixel column
//             :  is computed against zero-padding.
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
    input  logic        clk,        // The clock.
    input  logic        reset,      // The reset signal. Active high.
    output logic [15:0] addr,       // Address bus for data (halfword_t).
    input  logic [31:0] dataR,      // The data bus (word_t).
    output logic [31:0] dataW,      // The data bus (word_t).
    output logic        en,         // Request signal for data.
    output logic        we,          // Read/Write signal for data.
    input  logic        start,
    output logic        finish
);

  // ---------------------------------------------------
  // Image geometry (words are 4 pixels)
  // ---------------------------------------------------
  localparam int          WORDS_PER_ROW = 352 / 4;                   // 88
  localparam int          LAST_WORD     = WORDS_PER_ROW - 1;         // 87
  localparam int          LAST_ROW      = 288 - 2;                   // 286 (row 287 has no row below)
  localparam logic [15:0] DST_BASE      = 16'((352 * 288) / 4);      // 25344, start of processed image

  // ---------------------------------------------------
  // State machine
  // ---------------------------------------------------
  typedef enum logic [2:0] {
    IDLE,   // wait for start
    INIT,   // start of a new image row: clear window, k = -1
    RD,     // read the 3 words of the new window column (4 cycles)
    SHIFT,  // shift the new column into the window
    CALC,   // Sobel for the 4 pixels of word k -> outreg
    WR,     // write outreg to the processed image
    DONE    // raise finish until start is released
  } state_t;

  state_t state, state_next;

  // ---------------------------------------------------
  // Registers
  // ---------------------------------------------------
  logic        [8:0]  i;          // current output row, 1..286
  logic signed [7:0]  k;          // current output word in the row, -1..87 (-1 = preload)
  logic        [1:0]  c;          // cycle counter inside RD
  logic        [31:0] win    [3][3];  // [row: i-1, i, i+1][column: word k-1, k, k+1]
  logic        [31:0] newcol [3];     // words captured from RAM: [row i-1, row i, row i+1]
  logic        [31:0] outreg;         // 4 result pixels

  // ---------------------------------------------------
  // Sobel datapath (combinational): 4 pixels -> 4 saturated results
  // ---------------------------------------------------
  logic [31:0] sobel_out;

  always_comb begin
    logic [95:0]        line [3];   // {right word, centre word, left word} per row
    logic signed [12:0] s11, s12, s13, s21, s23, s31, s32, s33;
    logic signed [12:0] dx, dy, mag;

    for (int r = 0; r < 3; r++) begin
      line[r] = {win[r][2], win[r][1], win[r][0]};
    end

    sobel_out = '0;
    for (int j = 0; j < 4; j++) begin
      // Byte (4+j) of `line` is pixel j of the centre word; neighbours are +-1 byte.
      // Row 0 = i-1 (s1x), row 1 = i (s2x), row 2 = i+1 (s3x).
      s11 = 13'({1'b0, line[0][8*(3+j) +: 8]});
      s12 = 13'({1'b0, line[0][8*(4+j) +: 8]});
      s13 = 13'({1'b0, line[0][8*(5+j) +: 8]});
      s21 = 13'({1'b0, line[1][8*(3+j) +: 8]});
      s23 = 13'({1'b0, line[1][8*(5+j) +: 8]});
      s31 = 13'({1'b0, line[2][8*(3+j) +: 8]});
      s32 = 13'({1'b0, line[2][8*(4+j) +: 8]});
      s33 = 13'({1'b0, line[2][8*(5+j) +: 8]});

      dx  = (s13 - s11) + 2 * (s23 - s21) + (s33 - s31);
      dy  = (s11 - s31) + 2 * (s12 - s32) + (s13 - s33);
      mag = (dx < 0 ? -dx : dx) + (dy < 0 ? -dy : dy);

      sobel_out[8*j +: 8] = (mag > 13'sd255) ? 8'hFF : mag[7:0];
    end
  end

  // ---------------------------------------------------
  // Next-state logic
  // ---------------------------------------------------
  always_comb begin
    state_next = state;
    case (state)
      IDLE:  if (start)       state_next = INIT;
      INIT:                   state_next = RD;
      RD:    if (c == 2'd3)   state_next = SHIFT;
      SHIFT: state_next = (k >= 0) ? CALC : RD;   // k == -1: preload step, no output
      CALC:                   state_next = WR;
      WR: begin
        if (k == 8'sd87) begin
          state_next = (i == 9'(LAST_ROW)) ? DONE : INIT;
        end else begin
          state_next = RD;
        end
      end
      DONE:  if (!start)      state_next = IDLE;
      default:                state_next = IDLE;
    endcase
  end

  // ---------------------------------------------------
  // Registers / datapath updates
  // ---------------------------------------------------
  always_ff @(posedge clk) begin
    if (reset) begin
      state  <= IDLE;
      i      <= 9'd1;
      k      <= -8'sd1;
      c      <= 2'd0;
      outreg <= '0;
      for (int r = 0; r < 3; r++) begin
        newcol[r] <= '0;
        for (int col = 0; col < 3; col++) win[r][col] <= '0;
      end
    end else begin
      state <= state_next;

      case (state)
        IDLE: begin
          if (start) i <= 9'd1;
        end

        INIT: begin
          k <= -8'sd1;
          c <= 2'd0;
          for (int r = 0; r < 3; r++) begin
            for (int col = 0; col < 3; col++) win[r][col] <= '0;
          end
        end

        RD: begin
          // The RAM has a one-cycle read latency: the word addressed in cycle c
          // is available on dataR in cycle c+1. Past the last word of the row
          // there is nothing to read; zero-pad the right boundary instead.
          c <= (c == 2'd3) ? 2'd0 : c + 2'd1;
          case (c)
            2'd1: newcol[0] <= (k == 8'sd87) ? 32'd0 : dataR;   // row i-1
            2'd2: newcol[1] <= (k == 8'sd87) ? 32'd0 : dataR;   // row i
            2'd3: newcol[2] <= (k == 8'sd87) ? 32'd0 : dataR;   // row i+1
            default: ;
          endcase
        end

        SHIFT: begin
          for (int r = 0; r < 3; r++) begin
            win[r][0] <= win[r][1];
            win[r][1] <= win[r][2];
            win[r][2] <= newcol[r];
          end
          if (k < 0) k <= 8'sd0;      // preload done; the next RD fetches word 1
        end

        CALC: begin
          outreg <= sobel_out;
        end

        WR: begin
          if (k == 8'sd87) begin
            if (i != 9'(LAST_ROW)) i <= i + 9'd1;
          end else begin
            k <= k + 8'sd1;
          end
        end

        default: ;
      endcase
    end
  end

  // ---------------------------------------------------
  // Outputs (Moore)
  // ---------------------------------------------------
  logic [15:0] rd_row;     // image row addressed in the current RD cycle
  logic [15:0] rd_word;    // word index addressed in the current RD cycle (k+1)

  always_comb begin
    rd_row  = 16'(i) - 16'd1 + 16'(c);       // c=0: i-1, c=1: i, c=2: i+1
    rd_word = 16'(k + 8'sd1);                // only used when k >= -1
  end

  always_comb begin
    en     = 1'b0;
    we     = 1'b0;
    addr   = '0;
    dataW  = outreg;
    finish = 1'b0;

    case (state)
      RD: begin
        // Issue the three reads in c = 0, 1, 2. In c = 3 the last word is
        // only collected. No reads at all after the last word of a row.
        if (c != 2'd3 && k != 8'sd87) begin
          en   = 1'b1;
          we   = 1'b0;
          addr = rd_row * 16'(WORDS_PER_ROW) + rd_word;
        end
      end

      WR: begin
        en   = 1'b1;
        we   = 1'b1;
        addr = DST_BASE + 16'(i) * 16'(WORDS_PER_ROW) + 16'(k);
      end

      DONE: finish = 1'b1;

      default: ;
    endcase
  end

endmodule
