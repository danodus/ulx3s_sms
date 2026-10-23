`default_nettype none
module loader_overlay
(
  input  wire        clk,
  input  wire [9:0]  hc,
  input  wire [9:0]  vc,
  input  wire        enable,
  input  wire [7:0]  menu_ch,
  output wire [9:0]  menu_char_idx,
  input  wire [7:0]  sel_row,

  output reg  [7:0]  ov_r,
  output reg  [7:0]  ov_g,
  output reg  [7:0]  ov_b,
  output reg         ov_active
);

  localparam HA = 640;
  localparam VA = 480;
  localparam COLS = 40;
  localparam ROWS = 16;
  localparam MARGIN_X = 80;
  localparam MARGIN_Y = 96;

  reg [7:0] font_rom [0:1023];

  initial $readmemh("../src/font8x8.hex", font_rom);

  wire in_frame = enable && (hc < HA) && (vc < VA);
  wire [9:0] px = hc;
  wire [9:0] py = vc;

  wire in_panel = in_frame &&
                  (px >= MARGIN_X) && (px < MARGIN_X + COLS * 8) &&
                  (py >= MARGIN_Y) && (py < MARGIN_Y + ROWS * 8);

  wire [5:0] col = (px - MARGIN_X) >> 3;
  wire [3:0] row = (py - MARGIN_Y) >> 3;
  wire [2:0] bitx = (px - MARGIN_X) & 7;
  wire [2:0] bity = (py - MARGIN_Y) & 7;

  wire [9:0] char_idx = row * COLS + col;
  assign menu_char_idx = char_idx;
  wire [7:0] ch = (in_panel && row < ROWS && col < COLS) ? menu_ch : 8'h20;

  wire [9:0] font_a = {ch[6:0] - 7'h20, bity};
  wire [7:0] glyph = (ch >= 8'h20 && ch <= 8'h7e) ? font_rom[font_a] : 8'h00;

  wire pixel_on = in_panel && glyph[7-bitx];
  /* sel_row >= ROWS hides the bar (used while a status line is shown). */
  wire sel_row_hit = in_panel && (sel_row < ROWS) && (row == sel_row[3:0]);

  always @(posedge clk) begin
    ov_active <= in_frame;
    if (!in_frame) begin
      ov_r <= 8'd0;
      ov_g <= 8'd0;
      ov_b <= 8'd0;
    end else if (pixel_on) begin
      if (sel_row_hit) begin
        ov_r <= 8'hff;
        ov_g <= 8'hff;
        ov_b <= 8'hff;
      end else begin
        ov_r <= 8'hc0;
        ov_g <= 8'hd0;
        ov_b <= 8'hff;
      end
    end else if (sel_row_hit) begin
      ov_r <= 8'h50;
      ov_g <= 8'h50;
      ov_b <= 8'h90;
    end else if (in_panel) begin
      ov_r <= 8'h18;
      ov_g <= 8'h18;
      ov_b <= 8'h28;
    end else begin
      ov_r <= 8'h08;
      ov_g <= 8'h08;
      ov_b <= 8'h10;
    end
  end

endmodule
`default_nettype wire
