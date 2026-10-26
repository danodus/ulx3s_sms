`default_nettype none
module loader_soc
(
  input  wire        clk,
  input  wire [9:0]  raster_hc,
  input  wire [9:0]  raster_vc,
  input  wire        cpuClockEnable,
  input  wire        reset,
  input  wire        cancel,
  input  wire        active,

  input  wire [6:0]  pad_btn,
  input  wire        pad_u,
  input  wire        pad_d,
  input  wire        pad_a,

  output wire        sd_mosi,
  input  wire        sd_miso,
  output wire        sd_clk,
  output wire        sd_cs_n,

  output wire [7:0]  ov_r,
  output wire [7:0]  ov_g,
  output wire [7:0]  ov_b,
  output wire        ov_active,

  output wire        card_weB,
  output wire [23:0] card_addrB,
  output wire [7:0]  card_dinB,
  output wire        card_load_done,
  output wire        card_codemasters,
  output wire [31:0] card_rom_len
);

  // 32 KiB is shared by ULX3S and IcePi Zero. A 48 KiB array is
  // addressed with 14 bits, so Yosys maps it as 64 KiB and the
  // ECP5-25 runs out of block RAM. The menu image ends near 23 KiB,
  // which leaves about 10 KiB of stack.
  localparam NRV_RAM = 32 * 1024;
  localparam RAM_WORDS = NRV_RAM / 4;
  localparam RAM_AW = $clog2(RAM_WORDS);

  `include "loader_io_bits.v"

  wire [31:0] mem_address;
  wire [31:0] mem_wdata;
  wire [31:0] mem_rdata;
  wire  [3:0] mem_wmask;
  wire        mem_rstrb;
  wire        mem_rbusy;
  wire        mem_wbusy;
  wire        mem_wstrb = |mem_wmask;

  wire mem_address_is_io  = mem_address[22];
  wire mem_address_is_ram = !mem_address[22];
  wire [19:0] io_word_address = mem_address[21:2];
  wire        io_rstrb = mem_rstrb && mem_address_is_io;
  wire        io_wstrb = mem_wstrb && mem_address_is_io;
  wire [31:0] io_wdata = mem_wdata;

  reg  [31:0] io_rdata;
  assign mem_rbusy = 1'b0;
  // The PAL raster holds cpuClockEnable low for a whole HDMI line.
  // A store that does not wait would post more bytes while the SDRAM
  // pump is stuck, and those bytes never reach the cartridge.

  wire [RAM_AW-1:0] ram_word_address = mem_address[RAM_AW+1:2];

  // One write port so this stays a memory. Several ports become
  // flip-flops and Yosys spends a long time on the address decode.
  (* ram_style = "block" *)
  (* no_rw_check *)
  reg [31:0] RAM[0:RAM_WORDS-1];
  reg [31:0] ram_rdata;

  initial begin
    $readmemh("../firmware/sdmenu/firmware.hex", RAM);
  end

  reg [7:0] menu_vram [0:1023];
  wire menu_io_we = active && io_wstrb && io_word_address[IO_OVERLAY_bit] &&
                    io_wdata[25] && !io_wdata[24];

  always @(posedge clk) begin
    if (mem_address_is_ram && active) begin
      if (mem_wmask[0]) RAM[ram_word_address][ 7:0 ] <= mem_wdata[ 7:0 ];
      if (mem_wmask[1]) RAM[ram_word_address][15:8 ] <= mem_wdata[15:8 ];
      if (mem_wmask[2]) RAM[ram_word_address][23:16] <= mem_wdata[23:16];
      if (mem_wmask[3]) RAM[ram_word_address][31:24] <= mem_wdata[31:24];
    end
    if (menu_io_we)
      menu_vram[io_wdata[17:8]] <= io_wdata[7:0];
    ram_rdata <= RAM[ram_word_address];
  end

  assign mem_rdata = mem_address_is_io ? io_rdata : ram_rdata;

  reg [7:0] sel_row_r = 8'd0;

  wire [9:0] menu_char_idx;
  wire [7:0] menu_ch_byte = menu_vram[menu_char_idx];

  loader_overlay overlay_i(
    .clk(clk),
    .hc(raster_hc),
    .vc(raster_vc),
    .enable(active),
    .menu_ch(menu_ch_byte),
    .menu_char_idx(menu_char_idx),
    .sel_row(sel_row_r),
    .ov_r(ov_r),
    .ov_g(ov_g),
    .ov_b(ov_b),
    .ov_active(ov_active)
  );

  wire [31:0] sdcard_rdata;
  SDCard sdcard_i(
    .clk(clk),
    .rstrb(io_rstrb),
    .wstrb(io_wstrb),
    .sel(io_word_address[IO_SDCARD_bit]),
    .wdata(io_wdata),
    .rdata(sdcard_rdata),
    .CLK(sd_clk),
    .MISO(sd_miso),
    .MOSI(sd_mosi),
    .CS_N(sd_cs_n)
  );

  /* R_btn_joy: [6]=right [5]=left [4]=down [3]=up [2]=A [1]=B */
  wire [5:0] buttons_packed = {
    pad_btn[3],
    pad_btn[4],
    pad_btn[1] | pad_btn[2],
    pad_btn[3],
    pad_btn[4],
    pad_btn[1] | pad_btn[2]
  };

  wire [31:0] buttons_rdata;
  Buttons buttons_i(
    .sel(io_word_address[IO_BUTTONS_bit]),
    .rdata(buttons_rdata),
    .BUTTONS(buttons_packed)
  );

  reg        byte_wstrb = 1'b0;
  reg [7:0]  byte_data = 8'd0;
  reg        set_mapper = 1'b0;
  reg        mapper_cm = 1'b0;
  reg [31:0] rom_length = 32'd0;
  reg        finalize = 1'b0;

  sdram_card_loader card_loader(
    .clk(clk),
    .cpuClockEnable(cpuClockEnable),
    .reset(reset),
    .cancel(cancel),
    .byte_wstrb(byte_wstrb),
    .byte_data(byte_data),
    .set_mapper(set_mapper),
    .mapper_cm(mapper_cm),
    .rom_length(rom_length),
    .finalize(finalize),
    .weB(card_weB),
    .addrB(card_addrB),
    .dinB(card_dinB),
    .load_done(card_load_done),
    .codemasters(card_codemasters),
    .rom_len(card_rom_len)
  );

  // byte_wstrb is the cycle before card_weB rises, so the store is
  // stalled from the moment it is posted until the pump finishes.
  assign mem_wbusy = byte_wstrb || card_weB;

  always @(posedge clk) begin
    byte_wstrb  <= 1'b0;
    set_mapper  <= 1'b0;
    finalize    <= 1'b0;

    if (active && io_wstrb) begin
      if (io_word_address[IO_OVERLAY_bit]) begin
        if (io_wdata[24])
          sel_row_r <= io_wdata[23:16];
      end else if (io_word_address[IO_SDRAM_BYTE_bit]) begin
        byte_data  <= io_wdata[7:0];
        byte_wstrb <= 1'b1;
      end else if (io_word_address[IO_SDRAM_CTL_bit]) begin
        // Bit 0 selects the mapper. Bit 1 releases the Z80. The
        // finish write is value 2, so it must not load bit 0 or a
        // Codemasters cart comes out of reset as a Sega cart.
        if (io_wdata[1])
          finalize <= 1'b1;
        else begin
          set_mapper <= 1'b1;
          mapper_cm  <= io_wdata[0];
        end
      end else if (io_word_address[IO_SDRAM_LEN_bit])
        rom_length <= io_wdata;
    end
  end

  always @(posedge clk) begin
    io_rdata <= 0
      | sdcard_rdata
      | buttons_rdata
      | (io_word_address[IO_SDRAM_CTL_bit] && io_rstrb ? {30'd0, card_load_done, 1'b0} : 32'd0);
  end

  FemtoRV32 #(
    .ADDR_WIDTH(24),
    .RESET_ADDR(32'h0)
  ) cpu(
    .clk(clk),
    .mem_addr(mem_address),
    .mem_wdata(mem_wdata),
    .mem_wmask(mem_wmask),
    .mem_rdata(mem_rdata),
    .mem_rstrb(mem_rstrb),
    .mem_rbusy(mem_rbusy),
    .mem_wbusy(mem_wbusy),
    /* FemtoRV reset is active-low: 0 holds the core in reset. */
    .reset(active && !reset)
  );

endmodule
`default_nettype wire
