`default_nettype none
module sms
#(
  parameter c_vga_out     = 0, // 0; Just HDMI, 1: VGA and HDMI
  parameter c_lcd_hex     = 0, // SPI LCD HEX decoder
  parameter c_diag        = 1, // 0: No led diagnostcs, 1: led diagnostics
  // Board oscillator. ULX3S is 25 MHz. IcePi Zero is 50 MHz.
  // NTSC pixel/CPU/PSG clocks are 25 MHz. The PAL build uses 27 MHz.
  parameter c_clk_in_hz   = 25_000_000
)
(
  input         clk_25mhz,
  // Buttons
  input [6:0]   btn,
  // Switches
  input [3:0]   sw = 4'b0,
  // HDMI
`ifdef SYNTHESIS
  output [3:0]  gpdi_dp,
  output [3:0]  gpdi_dn,
`else // SYNTHESIS
    output       vga_hsync,
    output       vga_vsync,
    output [7:0] vga_r,
    output [7:0] vga_g,
    output [7:0] vga_b,  
`endif // SYNTHESIS
  // USB HID Host
  inout	        usb_fpga_bd_dn,
  inout	        usb_fpga_bd_dp,
  output        usb_fpga_pu_dp,
  output        usb_fpga_pu_dn,
`ifdef ICEPI
  // Second USB host socket (IcePi Zero USB2). Controller 2.
  inout         usb2_dn,
  inout         usb2_dp,
  output        usb2_pu_dp,
  output        usb2_pu_dn,
`endif
  // USB serial ROM loader. WiFi pins stay in the port list so the
  // board constraints still match; they are held idle.
  input         ftdi_txd,
  output        ftdi_rxd,
  input         wifi_txd,
  output        wifi_rxd,
  input         wifi_gpio16,
  input         wifi_gpio5,
  output        wifi_gpio0,
  output        wifi_en,

  inout  sd_clk, sd_cmd,
  inout   [3:0] sd_d,

  output sdram_csn,       // chip select
  output sdram_clk,       // clock to SDRAM
  output sdram_cke,       // clock enable to SDRAM
  output sdram_rasn,      // SDRAM RAS
  output sdram_casn,      // SDRAM CAS
  output sdram_wen,       // SDRAM write-enable
  output [12:0] sdram_a,  // SDRAM address bus
  output  [1:0] sdram_ba, // SDRAM bank-address
  output  [1:0] sdram_dqm,// byte select
  inout  [15:0] sdram_d,  // data bus to/from SDRAM

  inout  [27:0] gp,gn,
  // SPI display
  output        oled_csn,
  output        oled_clk,
  output        oled_mosi,
  output        oled_dc,
  output        oled_resn,
  // Leds
  output [7:0]  led
`ifdef SYNTHESIS
  ,
  // Open-drain PROGRAMN. Held low after SELECT has been down for 2 s,
  // which reloads the bitstream at the flash address that this image
  // names as the next boot (the other video standard).
  output        user_programn
`endif
);

  // I/O ports
  wire vdp_data_port = cpuAddress[7:6] == 2 && !cpuAddress[0];
  wire vdp_ctrl_port = cpuAddress[7:6] == 2 && cpuAddress[0];

  // The PSG ignores A0, so a write anywhere in $40-$7F reaches it.
  // Codemasters (Cosmic Spacehead, Micro Machines, Fantastic Dizzy)
  // write the sound data to $7E. Reads of $7E/$7F are still the counters.
  wire psg_write_port = cpuAddress[7:6] == 1;

  wire joypad_0_port = cpuAddress[7:6] == 3 && !cpuAddress[0];
  wire joypad_1_port = cpuAddress[7:6] == 3 && cpuAddress[0];

  wire mem_ctrl_port = cpuAddress[7:6] == 0 && !cpuAddress[0];
  wire joypad_ctrl_port = cpuAddress[7:6] == 0 && cpuAddress[0];

  wire v_counter_port = cpuAddress[7:6] == 1 && !cpuAddress[0];
  wire h_counter_port = cpuAddress[7:6] == 1 && cpuAddress[0];

  wire [7:0] v_counter;
  wire [7:0] h_counter;

  reg [7:0] r_mem_ctrl;
  reg [7:0] r_joy_ctrl;

  // pull-ups for us2 connector 
  assign usb_fpga_pu_dp = 1'b0;
  assign usb_fpga_pu_dn = 1'b0;
  
  assign wifi_rxd = 1'b1;
  assign wifi_gpio0 = 1'b1;
  /* ESP32 shares the SD pins. Hold it in reset so the card can be read. */
  assign wifi_en = 1'b0;

  // VGA (should be assigned to some gp/gn outputs
  wire   [7:0]  red;
  wire   [7:0]  green;
  wire   [7:0]  blue;
  wire          hSync;
  wire          vSync;
  wire [9:0]    raster_hc;
  wire [9:0]    raster_vc;
  wire [9:0]    frame_height;
  // Raster counters. On the FPGA these are hdmi cx/cy. Simulation has no
  // ODDRX1F, so it counts the same 800 by frame_height frame locally.
`ifdef SYNTHESIS
  wire [11:0]   hdmi_cx;
  wire [11:0]   hdmi_cy;
  wire [9:0]    cx = hdmi_cx[9:0];
  wire [9:0]    cy = hdmi_cy[9:0];
  wire          sample_strobe;
  wire signed [15:0] audio_sample;
`else
  reg [9:0]     cx = 0;
  reg [9:0]     cy = 0;
`endif
  
  generate
    genvar i;
    if (c_vga_out) begin
      for(i = 0; i < 4; i = i+1) begin
        assign gp[10-i] = blue[4+i];
        assign gn[3-i] = green[4+i];
        assign gn[10-i] = red[4+i];
      end
      assign gp[2] = vSync;
      assign gp[3] = hSync;
    end 
  endgenerate

  // Led diagnostics
  reg [15:0] diag16;

  generate 
    genvar i2;
    if (c_diag) begin
      for(i2 = 0; i2 < 4; i2 = i2+1) begin
        assign gn[17-i2] = diag16[8+i2];
        assign gp[17-i2] = diag16[12+i2];
        assign gn[24-i2] = diag16[i2];
        assign gp[24-i2] = diag16[4+i2];
      end
    end
  endgenerate
  
  // CPU registers
  wire          n_WR;
  wire          n_RD;
  wire          n_INT;
  wire [15:0]   cpuAddress;
  wire [7:0]    cpuDataOut;
  wire [7:0]    cpuDataIn;
  wire          n_memWR;
  wire          n_memRD;
  wire          n_ioWR;
  wire          n_ioRD;
  wire          n_MREQ;
  wire          n_IORQ;
  wire          n_M1;
  wire          n_kbdCS;
  wire          n_int;

  reg           cpuClockEnable = 0;
  reg           cpuClockEnable1; 
  wire          cpuClockEdge = cpuClockEnable && !cpuClockEnable1;
  wire [7:0]    ramOut;
  wire [7:0]    biosOut;
  wire [7:0]    romOut;

  reg [7:0]   slot0, slot1, slot2;
  reg [7:0]   mem_misc;
  // Codemasters carts bank through $0000/$4000/$8000 and power up
  // with slot 2 on bank 0. load_rom.py sends the type.
`ifdef SYNTHESIS
  wire        codemasters;
`else
  reg         codemasters = 1'b0;
`endif
  
  // ===============================================================
  // System Clock generation
  // ===============================================================
`ifdef SYNTHESIS
  wire clk_sdram_locked;
  wire clk_usb_locked;
  wire clk_usb;
  wire clk_hdmi;
  wire clk_vga;
  wire cpuClock;
  wire clk_sdram;
`ifdef PAL
  // 135, 27, and 81 MHz share a 405 MHz VCO, so the SDRAM clock is
  // exactly 3x the pixel clock and cannot drift against it. A separate
  // 100 MHz PLL does drift, and the BIOS checksum then reads bad bytes.
  // 108 MHz (4x) also divides that family of VCOs, but two RAS-to-CAS
  // cycles there are 18.5 ns and these chips need 20 ns. At 81 MHz the
  // two cycles are 24.7 ns. The second PLL is only the 12 MHz USB clock,
  // derived from a 100 MHz primary the same way as before.
  wire clk_hdmi_locked;
  wire clk_sys_locked;
  wire [3:0] hdmi_clocks;
  wire [3:0] sys_clocks;
  assign clk_sdram_locked = clk_hdmi_locked;
  assign clk_usb_locked = clk_sys_locked;
  ecp5pll
  #(
    .in_hz(c_clk_in_hz),
    .out0_hz(135*1000000),
    .out1_hz( 27*1000000),
    .out2_hz( 81*1000000),                // SDRAM core
    .out3_hz( 81*1000000), .out3_deg(180) // SDRAM chip
  )
  ecp5pll_hdmi
  (
    .clk_i(clk_25mhz),
    .clk_o(hdmi_clocks),
    .locked(clk_hdmi_locked)
  );
  ecp5pll
  #(
    .in_hz(c_clk_in_hz),
    .out0_hz(100*1000000),
    .out1_hz( 12*1000000)
  )
  ecp5pll_sys
  (
    .clk_i(clk_25mhz),
    .clk_o(sys_clocks),
    .locked(clk_sys_locked)
  );
  assign clk_hdmi  = hdmi_clocks[0];
  assign clk_vga   = hdmi_clocks[1];
  assign cpuClock  = hdmi_clocks[1];
  assign clk_sdram = hdmi_clocks[2];
  assign sdram_clk = hdmi_clocks[3];
  assign clk_usb   = sys_clocks[1];
`else
  wire [3:0] clocks;
  ecp5pll
  #(
      .in_hz(c_clk_in_hz),
    .out0_hz(125*1000000),
    .out1_hz( 25*1000000),
    .out2_hz(100*1000000),                // SDRAM core
    .out3_hz(100*1000000), .out3_deg(180) // SDRAM chip 45-330:ok 0-30:not
  )
  ecp5pll_inst
  (
    .clk_i(clk_25mhz),
    .clk_o(clocks),
    .locked(clk_sdram_locked)
  );
  assign clk_hdmi  = clocks[0];
  assign clk_vga   = clocks[1];
  assign cpuClock  = clocks[1];
  assign clk_sdram = clocks[2];
  assign sdram_clk = clocks[3]; // phase shifted for chip
`endif
`else // SYNTHESIS
  wire clk_vga   = clk_25mhz;
  wire cpuClock  = clk_25mhz;

  always @(posedge clk_vga) begin
`ifdef PAL
    if (cx == 10'd863) begin
`else
    if (cx == 10'd799) begin
`endif
      cx <= 10'd0;
      if (cy >= frame_height - 10'd1)
        cy <= 10'd0;
      else
        cy <= cy + 10'd1;
    end else
      cx <= cx + 10'd1;
  end
`endif // SYNTHESIS

  // ===============================================================
  // USB HID Host Clock generation
  // ===============================================================
`ifdef SYNTHESIS
`ifndef PAL
  // usb_pll is two PLLs and only accepts 25 MHz. An ECP5-25 has two
  // PLLs total, so a 50 MHz board uses the single 100-to-12 stage.
  // The PAL build takes 12 MHz from the system PLL instead.
  generate
    if (c_clk_in_hz == 25_000_000) begin : usb_clk_25
      usb_pll ecp5pll_usb_inst
      (
        .clkin(clk_25mhz),
        .clk12(clk_usb),
        .clk100(),
        .locked(clk_usb_locked)
      );
    end else begin : usb_clk_50
      usb_pll_12 ecp5pll_usb_inst
      (
        .clkin(clk_sdram),
        .rst(~clk_sdram_locked),
        .clk12(clk_usb),
        .locked(clk_usb_locked)
      );
    end
  endgenerate
`endif // PAL
`endif
 
  // ===============================================================
  // Joystick
  // ===============================================================
  wire [6:0] usb_gamepad_btn;
  reg [6:0] R_btn_joy;
  always @(posedge cpuClock)
    R_btn_joy <= btn | usb_gamepad_btn;

  // ===============================================================
  // Reset generation
  // ===============================================================
  `ifdef SYNTHESIS
  reg [15:0] pwr_up_reset_counter = 0;
  `else // SYNTHESIS
  reg [2:0] pwr_up_reset_counter = 0;
  `endif // SYNTHESIS
  wire       pwr_up_reset_n = &pwr_up_reset_counter;

  // HDMI starts with a reset of 65536 pixel clocks, after the PLLs lock,
  // like the color-bar demo that the old Bravia accepts. The CPU divider
  // is held at phase 0 for the same interval and both leave reset on the
  // same clock, so cx = 0 still lines up with divider phase 0.
`ifdef SYNTHESIS
  wire       raster_rst = !pwr_up_reset_n;
`else
  wire       raster_rst = 1'b0;
`endif

  always @(posedge cpuClock) begin
     if (!pwr_up_reset_n)
`ifdef SYNTHESIS
       pwr_up_reset_counter <= (clk_sdram_locked && clk_usb_locked) ? pwr_up_reset_counter + 1 : 0;
`else
       pwr_up_reset_counter <= pwr_up_reset_counter + 1;
`endif
  end

  // ===============================================================
  // USB Gamepad
  // ===============================================================
  wire [1:0] usb_type;
  wire game_l, game_r, game_u, game_d, game_a, game_b, game_x, game_y;
  wire game_sel, game_sta;
  // Controller 2 (IcePi USB2). Tied off when that port is not built.
  wire [1:0] usb2_type;
  wire game2_l, game2_r, game2_u, game2_d, game2_a, game2_b;
  wire game2_sel, game2_sta;

  wire usb_reset = !pwr_up_reset_n | !btn[0];

`ifdef SYNTHESIS
  usb_hid_host usb (
    .usbclk(clk_usb),
    .usbrst_n(!usb_reset),
    .usb_dm(usb_fpga_bd_dn),
    .usb_dp(usb_fpga_bd_dp),
    .typ(usb_type),
    .report(),
    .key_modifiers(), .key1(), .key2(), .key3(), .key4(),
    .mouse_btn(), .mouse_dx(), .mouse_dy(),
    .game_l(game_l), .game_r(game_r), .game_u(game_u), .game_d(game_d),
    .game_a(game_a), .game_b(game_b), .game_x(game_x), .game_y(game_y), 
    .game_sel(game_sel), .game_sta(game_sta),
    .conerr(), .dbg_hid_report()
  );
`endif

  assign usb_gamepad_btn = {game_r, game_l, game_d, game_u, game_a, game_b, 1'b0};

  // Same 12 MHz clock and reset as controller 1. IcePi only: ULX3S
  // has no second host socket, and sms is that board's top module.
`ifdef ICEPI
  // Host mode: 15 kOhm pulldowns on, 1.5 kOhm device pull-ups off.
  assign usb2_pu_dp = 1'b0;
  assign usb2_pu_dn = 1'b0;
`ifdef SYNTHESIS
  usb_hid_host usb2 (
    .usbclk(clk_usb),
    .usbrst_n(!usb_reset),
    .usb_dm(usb2_dn),
    .usb_dp(usb2_dp),
    .typ(usb2_type),
    .report(),
    .key_modifiers(), .key1(), .key2(), .key3(), .key4(),
    .mouse_btn(), .mouse_dx(), .mouse_dy(),
    .game_l(game2_l), .game_r(game2_r), .game_u(game2_u), .game_d(game2_d),
    .game_a(game2_a), .game_b(game2_b), .game_x(), .game_y(),
    .game_sel(game2_sel), .game_sta(game2_sta),
    .conerr(), .dbg_hid_report()
  );
`else
  assign usb2_type = 2'b00;
  assign game2_l = 1'b0;
  assign game2_r = 1'b0;
  assign game2_u = 1'b0;
  assign game2_d = 1'b0;
  assign game2_a = 1'b0;
  assign game2_b = 1'b0;
  assign game2_sel = 1'b0;
  assign game2_sta = 1'b0;
`endif
`else
  assign usb2_type = 2'b00;
  assign game2_l = 1'b0;
  assign game2_r = 1'b0;
  assign game2_u = 1'b0;
  assign game2_d = 1'b0;
  assign game2_a = 1'b0;
  assign game2_b = 1'b0;
  assign game2_sel = 1'b0;
  assign game2_sta = 1'b0;
`endif

  // Player 1 directions stay on port $DC. Same packing as player 1,
  // sampled on the CPU clock: [5] right, [4] left, [3] down, [2] up,
  // [1] A, [0] B.
  reg [5:0] p2_joy = 6'b0;
  always @(posedge cpuClock)
    p2_joy <= {game2_r, game2_l, game2_d, game2_u, game2_a, game2_b};
  reg joypad2 = 1'b0;

  // The video standard is the bitstream. PAL is VIC 17 (312 SMS
  // lines). NTSC is the 524-line raster. Holding SELECT for 2 s
  // reloads the other bitstream from flash (multiboot via PROGRAMN).
`ifdef PAL
  wire pal_mode = 1'b1;
`else
  wire pal_mode = 1'b0;
`endif
  // Pause NMI. Held low for the whole START press, and kept high in
  // reset and in the menu.
  reg nmi_n = 1'b1;

  // ===============================================================
  // CPU
  // ===============================================================
  wire [15:0] pc;
  
  wire       load_done;
  wire       loader_we;
  wire [23:0] loader_addr;
  wire [7:0] loader_data;
`ifdef SYNTHESIS
  wire [31:0] rom_len;
  wire       serial_load_done;
  wire       serial_busy;
  wire       serial_codemasters;
  wire [31:0] serial_rom_len;
  wire       serial_we;
  wire [23:0] serial_addr;
  wire [7:0] serial_data;
  wire       card_we;
  wire [23:0] card_addr;
  wire [7:0] card_data;
  wire       card_load_done;
  wire       card_codemasters;
  wire [31:0] card_rom_len;
  wire       loader_menu = !load_done;
  wire       l_sd_mosi, l_sd_clk, l_sd_cs_n;
  wire [7:0] ov_r, ov_g, ov_b;
  wire       ov_active;
  wire [7:0] hdmi_r, hdmi_g, hdmi_b;
`else
  reg [31:0] rom_len = 0;
  wire [7:0] hdmi_r, hdmi_g, hdmi_b;
`endif

  // Cartridge ROM ignores address bits above its size, so a bank
  // number such as $87 on a 256KB cart reads bank 7. The next
  // power-of-two length, minus one, is that mirror mask.
  function [23:0] pow2_mask;
    input [31:0] len;
    reg [31:0] v;
    begin
      v = len - 32'd1;
      v = v | (v >> 1);
      v = v | (v >> 2);
      v = v | (v >> 4);
      v = v | (v >> 8);
      v = v | (v >> 16);
      pow2_mask = v[23:0];
    end
  endfunction

`ifdef SYNTHESIS
  // Power-up, the power button, and SELECT return to the ROM menu.
  // The Z80 stays reset until a ROM is loaded. A USB upload also
  // holds it in reset, then boots that ROM, including when the
  // previous ROM came from the SD menu. Each pad is separate.
  reg menu_req = 1'b0;
  reg wait_sta1 = 1'b0;
  reg wait_sta2 = 1'b0;
  reg nmi_pad1 = 1'b0;
  reg nmi_pad2 = 1'b0;
  reg sel1_down = 1'b0;
  reg sel2_down = 1'b0;
  // SELECT held for 2 s switches the video standard by reloading the
  // other bitstream. A pad must be seen released first, so a button
  // still held across the reload does not bounce straight back.
`ifdef PAL
  localparam [25:0] SEL_HOLD_CLKS = 26'd54_000_000;
`else
  localparam [25:0] SEL_HOLD_CLKS = 26'd50_000_000;
`endif
  reg        sel1_armed = 1'b0;
  reg        sel2_armed = 1'b0;
  reg [25:0] sel1_hold = 26'd0;
  reg [25:0] sel2_hold = 26'd0;
  reg        reload_req = 1'b0;
  assign user_programn = reload_req ? 1'b0 : 1'bz;
  // The HID host registers the pads on the USB clock, so two flops
  // close the crossing.
  reg [1:0] sta1_sync = 2'b0;
  reg [1:0] sta2_sync = 2'b0;
  reg [1:0] sel1_sync = 2'b0;
  reg [1:0] sel2_sync = 2'b0;
  always @(posedge cpuClock) begin
    sta1_sync <= {sta1_sync[0], game_sta};
    sta2_sync <= {sta2_sync[0], game2_sta};
    sel1_sync <= {sel1_sync[0], game_sel};
    sel2_sync <= {sel2_sync[0], game2_sel};
    menu_req  <= 1'b0;

    if (!pwr_up_reset_n) begin
      wait_sta1 <= 1'b0;
      wait_sta2 <= 1'b0;
      nmi_pad1  <= 1'b0;
      nmi_pad2  <= 1'b0;
      sel1_down <= 1'b0;
      sel2_down <= 1'b0;
      sel1_armed <= 1'b0;
      sel2_armed <= 1'b0;
      sel1_hold <= 26'd0;
      sel2_hold <= 26'd0;
    end else begin
      if (sta1_sync[1] && !wait_sta1) begin
        wait_sta1 <= 1'b1;
        if (!loader_menu)
          nmi_pad1 <= 1'b1;
      end else if (!sta1_sync[1]) begin
        wait_sta1 <= 1'b0;
        nmi_pad1  <= 1'b0;
      end

      if (sta2_sync[1] && !wait_sta2) begin
        wait_sta2 <= 1'b1;
        if (!loader_menu)
          nmi_pad2 <= 1'b1;
      end else if (!sta2_sync[1]) begin
        wait_sta2 <= 1'b0;
        nmi_pad2  <= 1'b0;
      end

      // A short SELECT press returns to the menu on release. Held for
      // 2 s, in a game or in the menu, it asserts PROGRAMN instead and
      // the FPGA reloads the other video standard from flash.
      if (!sel1_sync[1]) sel1_armed <= 1'b1;
      if (!sel2_sync[1]) sel2_armed <= 1'b1;

      if (sel1_sync[1] && sel1_armed && !reload_req) begin
        sel1_hold <= sel1_hold + 26'd1;
        if (sel1_hold == SEL_HOLD_CLKS)
          reload_req <= 1'b1;
      end else
        sel1_hold <= 26'd0;

      if (sel2_sync[1] && sel2_armed && !reload_req) begin
        sel2_hold <= sel2_hold + 26'd1;
        if (sel2_hold == SEL_HOLD_CLKS)
          reload_req <= 1'b1;
      end else
        sel2_hold <= 26'd0;

      if (sel1_sync[1] && load_done) begin
        sel1_down <= 1'b1;
      end else begin
        if (sel1_down && load_done)
          menu_req <= 1'b1;
        sel1_down <= 1'b0;
      end

      if (sel2_sync[1] && load_done) begin
        sel2_down <= 1'b1;
      end else begin
        if (sel2_down && load_done)
          menu_req <= 1'b1;
        sel2_down <= 1'b0;
      end

      // Drop pause when the menu returns, even if START is still held.
      // The wait latch stays set until release, so the next ROM does
      // not see a new edge.
      if (loader_menu) begin
        nmi_pad1 <= 1'b0;
        nmi_pad2 <= 1'b0;
      end
    end

    nmi_n <= (pwr_up_reset_n && !loader_menu && (nmi_pad1 || nmi_pad2)) ? 1'b0 : 1'b1;
  end
  wire loader_reset = !pwr_up_reset_n | !btn[0] | menu_req;
  serial_loader
  serial_loader_inst
  (
    .clk(cpuClock),
    .cpuClockEnable(cpuClockEnable),
    .reset(loader_reset),
    .rxd(ftdi_txd),
    .txd(ftdi_rxd),
    .load_done(serial_load_done),
    .busy(serial_busy),
    .codemasters(serial_codemasters),
    .weB(serial_we),
    .addrB(serial_addr),
    .dinB(serial_data),
    .rom_len(serial_rom_len)
  );

  loader_soc loader_soc_i(
    .clk(cpuClock),
    .raster_hc(raster_hc),
    .raster_vc(raster_vc),
    .cpuClockEnable(cpuClockEnable),
    .reset(loader_reset),
    .cancel(serial_busy),
    .active(loader_menu),
    // Controller 2 uses the same Up/Down/A/B bits, so either pad
    // can move the highlight and open a folder or start a ROM.
    .pad_btn(R_btn_joy | {p2_joy, 1'b0}),
    .pad_u(game_u | p2_joy[2]),
    .pad_d(game_d | p2_joy[3]),
    .pad_a(game_a | p2_joy[1]),
    .sd_mosi(l_sd_mosi),
    .sd_miso(sd_d[0]),
    .sd_clk(l_sd_clk),
    .sd_cs_n(l_sd_cs_n),
    .ov_r(ov_r),
    .ov_g(ov_g),
    .ov_b(ov_b),
    .ov_active(ov_active),
    .card_weB(card_we),
    .card_addrB(card_addr),
    .card_dinB(card_data),
    .card_load_done(card_load_done),
    .card_codemasters(card_codemasters),
    .card_rom_len(card_rom_len)
  );

  assign load_done = (serial_load_done | card_load_done) & ~serial_busy;
  assign codemasters = card_load_done ? card_codemasters : serial_codemasters;
  assign rom_len     = card_load_done ? card_rom_len : serial_rom_len;
  assign loader_we   = serial_we | card_we;
  assign loader_addr = serial_we ? serial_addr : card_addr;
  assign loader_data = serial_we ? serial_data : card_data;

  assign sd_cmd  = loader_menu ? l_sd_mosi  : 1'bz;
  assign sd_clk  = loader_menu ? l_sd_clk   : 1'bz;
  assign sd_d[3] = loader_menu ? l_sd_cs_n  : 1'bz;
  /* DAT1/DAT2 stay high in SPI mode. Do not assign sd_d[0]:
     a 1'bz driver makes Yosys drop the MISO input. */
  assign sd_d[2] = loader_menu ? 1'b1 : 1'bz;
  assign sd_d[1] = loader_menu ? 1'b1 : 1'bz;

  assign hdmi_r = loader_menu ? ov_r : red;
  assign hdmi_g = loader_menu ? ov_g : green;
  assign hdmi_b = loader_menu ? ov_b : blue;
`else
  assign load_done = 1'b1;
  assign hdmi_r = red;
  assign hdmi_g = green;
  assign hdmi_b = blue;
`endif

  reg n_hard_reset;
  always @(posedge cpuClock)
    n_hard_reset <= pwr_up_reset_n & btn[0] & load_done;

  wire reset = !n_hard_reset;

  tv80n cpu1 (
    .reset_n(n_hard_reset),
    .clk(cpuClockEnable), // normal mode 3.5MHz
    //.wait_n(!R_btn_joy[1]),
    .wait_n(1'b1),
    .int_n(n_int),
    .nmi_n(nmi_n),
    .busrq_n(1'b1),
    .mreq_n(n_MREQ),
    .m1_n(n_M1),
    .iorq_n(n_IORQ),
    .wr_n(n_WR),
    .rd_n(n_RD),
    .A(cpuAddress),
    .di(cpuDataIn),
    .do(cpuDataOut),
    .pc(pc)
  );

  // ===============================================================
  // RAM
  // ===============================================================
  ram ram8k (
    .clk(cpuClock),
    .we(cpuAddress[15:14] == 3 && !n_memWR),
    .addr(cpuAddress[12:0]),
    .din(cpuDataOut),
    .dout(ramOut)
  );

  // Cartridge RAM. $FFFC bit 3 maps it over slot 2 ($8000-$BFFF),
  // in place of the ROM bank. Desert Speedtrap has 8KB of this and
  // no battery: it decompresses a tileset here, then copies the buffer
  // to VRAM. A13 is not wired on an 8KB chip, so $A000 mirrors $8000.
  wire        cart_ram_sel = mem_misc[3] && !codemasters && cpuAddress[15:14] == 2'd2;
  wire [7:0]  cartRamOut;
  ram cart_ram (
    .clk(cpuClock),
    .we(cart_ram_sel && !n_memWR),
    .addr(cpuAddress[12:0]),
    .din(cpuDataOut),
    .dout(cartRamOut)
  );

  // ===============================================================
  // GAME ROM (uses SDRAM)
  // ===============================================================

  wire [23:0] sdramAddress = cpuAddress[15:14] == 0 ? {slot0, cpuAddress[13:0]} :
                    cpuAddress[15:14] == 1 ? {slot1, cpuAddress[13:0]} :
                    cpuAddress[15:14] == 2 ? {slot2, cpuAddress[13:0]} : cpuAddress;
  wire [23:0] cart_addr = sdramAddress & pow2_mask(rom_len);

  `ifdef SYNTHESIS
  wire sdram_d_wr;
  wire [15:0] sdram_d_in, sdram_d_out;

  assign sdram_d = sdram_d_wr ? sdram_d_out : 16'hzzzz;
  assign sdram_d_in = sdram_d;
  sdram
  sdram_i
  (
   .sd_data_in(sdram_d_in),
   .sd_data_out(sdram_d_out),
   .sd_addr(sdram_a),
   .sd_dqm(sdram_dqm),
   .sd_cs(sdram_csn),
   .sd_ba(sdram_ba),
   .sd_we(sdram_wen),
   .sd_ras(sdram_rasn),
   .sd_cas(sdram_casn),
   // system interface
   .clk(clk_sdram),
   .clkref(cpuClockEnable),
   .init(!pwr_up_reset_n),
   .we_out(sdram_d_wr),
   // cpu/chipset interface
   .weA(0),
   .addrA(cart_addr),
   .oeA(cpuClockEnable),
   .dinA(0),
   .doutA(romOut),
   // Serial loader writes the cartridge here
   .weB(loader_we),
   .addrB(loader_addr),
   .dinB(loader_data),
   .oeB(0),
   .doutB()
  );
`else // SYNTHESIS
  reg [7:0] game_rom [0:524287];  // max: 512kB
  initial begin
    integer file, r;
    reg [15:0] cm_word, cm_comp;
    file = $fopen("cart.rom", "rb");
    r = $fread(game_rom, file);
    rom_len = r;
    $display("Nb bytes read: %d", r);
    $fclose(file);
    // load_rom.py tells the serial loader which mapper this is. The
    // sim reads the file itself, so it repeats that test here.
    if (r > 32'h7FFF) begin
      cm_word = {game_rom[32'h7FE7], game_rom[32'h7FE6]};
      cm_comp = {game_rom[32'h7FE9], game_rom[32'h7FE8]};
      codemasters = (cm_word != 16'd0) && ((cm_word + cm_comp) == 16'd0) &&
                    (game_rom[32'h7FEA] == 8'd0) && (game_rom[32'h7FEB] == 8'd0) &&
                    (game_rom[32'h7FEC] == 8'd0) && (game_rom[32'h7FED] == 8'd0) &&
                    (game_rom[32'h7FEE] == 8'd0) && (game_rom[32'h7FEF] == 8'd0) &&
                    (game_rom[32'h7FF0] == 8'h54) && (game_rom[32'h7FF1] == 8'h4D) &&
                    (game_rom[32'h7FF2] == 8'h52) && (game_rom[32'h7FF3] == 8'h20) &&
                    (game_rom[32'h7FF4] == 8'h53) && (game_rom[32'h7FF5] == 8'h45) &&
                    (game_rom[32'h7FF6] == 8'h47) && (game_rom[32'h7FF7] == 8'h41);
    end
    if (codemasters)
      $display("Codemasters mapper");
  end
  // Low 19 bits: the array is 512KB. cart_addr already mirrors at rom_len.
  assign romOut = game_rom[cart_addr[18:0]];
  // always @(posedge cpuClock) begin
  //   if (cpuAddress[15:14] < 3 && n_memRD == 1'b0 && r_mem_ctrl[3] == 1'b1)
  //     $display("%x, %x", sdramAddress, romOut);
  // end
`endif // SYNTHESIS
  
  // ===============================================================
  // BIOS ROM
  // ===============================================================
  rom #(.MEM_INIT_FILE("../roms/bios.mem")) bios_rom (
    .clk(cpuClock),
    .addr(cpuAddress[13:0]),
    .dout(biosOut)
  );

  // ===============================================================
  // VGA
  // ===============================================================
  wire [7:0]  vga_dout;
  reg [13:0]  vga_addr;
  wire        vga_wr = vdp_data_port && n_ioWR == 1'b0;
  wire        vga_rd = vdp_data_port && n_ioRD == 1'b0;
  reg         is_second_addr_byte = 0;
  reg [7:0]   first_addr_byte;
  reg [7:0]   r_vdp [0:10];
  wire        m1 = r_vdp[1][4];
  wire        m2 = r_vdp[0][1];
  wire        m3 = r_vdp[1][3];
  wire        m4 = r_vdp[0][2];
  wire [2:0]  mode = m4 ? 4 : m3 ? 3 : m2 ? 2 : m1 ? 1 : 0;
  // 224/240-line mode ignores bit 1 of R2 and adds $0700, so a value
  // of $0E addresses $3700. The 192-line decode of the same value is
  // $3800, four tile rows below the map the game filled in.
  wire        vdp_extended = r_vdp[0][1] & (r_vdp[1][3] | r_vdp[1][4]);
  wire [13:0] name_table_addr = vdp_extended ? ({r_vdp[2][3:2], 12'b0} | 14'h0700)
                                             : {r_vdp[2][3:1], 11'b0};
  wire [13:0] color_table_addr = mode == 2 ? {r_vdp[3][7], 13'b0} : {r_vdp[3], 6'b0};
  wire [13:0] font_addr = mode == 4 ? 0 : mode == 2 ? {r_vdp[4][2],13'b0} : {r_vdp[4], 11'b0};
  wire [13:0] sprite_attr_addr = {r_vdp[5][6:1], 8'b0};
  wire [13:0] sprite_pattern_table_addr = mode == 4 ? {r_vdp[6][2], 13'b0} : {r_vdp[6][2:0], 11'b0};
  wire [3:0]  overscan_color = r_vdp[7][3:0];
  wire [7:0]  x_scroll = r_vdp[8];
  wire [7:0]  y_scroll = r_vdp[9];
  wire [7:0]  line_counter = r_vdp[10];
  wire [15:0] vga_diag;
  reg         r_vga_rd;
  wire [4:0]  spritex;
  wire        sprite_collision;
  wire        too_many_sprites;
  wire        interrupt_flag;
  reg         cram_selected;

  // I/O ports
  always @(posedge cpuClock) begin
    if (!n_hard_reset) begin
      r_mem_ctrl <= 8'hf7;
      slot0 <= 0;
      slot1 <= 1;
      slot2 <= codemasters ? 8'd0 : 8'd2;
      mem_misc <= 0;
      r_joy_ctrl <= 0;
    end else if (cpuClockEdge) begin
      // VDP interface
      if (vga_wr) vga_addr <= vga_addr + 1;
      // Increment address on CPU cycle after IO read
      r_vga_rd <= vga_rd;
      if (r_vga_rd && !vga_rd) vga_addr <= vga_addr + 1;

      // Clear second address byte flag on VDP ctrl read or data read or write
      if ((vdp_ctrl_port && n_ioRD == 1'b0) || vga_rd || vga_wr) is_second_addr_byte <= 0;
      if (vdp_ctrl_port && n_ioWR == 1'b0) begin
        is_second_addr_byte <= ~is_second_addr_byte;
        if (is_second_addr_byte) begin
          if (!cpuDataOut[7]) begin // Ignores bit 6 which says if VRAM read or write is coming next
            vga_addr <= {cpuDataOut[5:0], first_addr_byte};
            cram_selected <= 0;
          end else if (cpuDataOut[7:6] == 3) begin // CRAM
            vga_addr <= first_addr_byte[5:0];
            cram_selected <= 1;
          end else if (cpuDataOut[7:6] == 2 && cpuDataOut[3:0] < 11) begin
            r_vdp[cpuDataOut[3:0]] <= first_addr_byte;
            // A register write still loads the address register.
            vga_addr[13:8] <= cpuDataOut[5:0];
          end else begin 
            vga_addr <= first_addr_byte[5:0];
            cram_selected <= 1;
          end
        end else begin
          // The low address byte is live after the first control write.
          // Cosmic Spacehead stores a byte before sending the high half.
          first_addr_byte <= cpuDataOut;
          vga_addr[7:0] <= cpuDataOut;
        end
      end else if (mem_ctrl_port && n_ioWR == 1'b0) begin
        r_mem_ctrl <= cpuDataOut; // Memory control write
      end else if (joypad_ctrl_port && n_ioWR == 1'b0) begin
        r_joy_ctrl <= cpuDataOut;
      end

      // Codemasters mirrors the bank register across each 16KB slot.
      // Sega uses $FFFC-$FFFF, and those writes also land in RAM.
      if (codemasters) begin
        if (n_memWR == 1'b0)
          case (cpuAddress[15:14])
            2'd0: slot0 <= cpuDataOut;
            2'd1: slot1 <= cpuDataOut;
            2'd2: slot2 <= cpuDataOut;
            default: ;
          endcase
      end else if (cpuAddress == 16'hfffc && n_memWR == 1'b0) mem_misc <= cpuDataOut;
      else if (cpuAddress == 16'hfffd && n_memWR == 1'b0) slot0 <= cpuDataOut;
      else if (cpuAddress == 16'hfffe && n_memWR == 1'b0) slot1 <= cpuDataOut;
      else if (cpuAddress == 16'hffff && n_memWR == 1'b0) slot2 <= cpuDataOut;
    end
  end
      
  // VIC 17 has 625 lines. 312 SMS lines use 624 of them. Hold the
  // last line so the 228-T-state divider stays aligned with hc.
`ifdef PAL
  wire pal_line_hold = (cy == 10'd624);
  wire [9:0] vdp_cx = pal_line_hold ? 10'd863 : cx;
  wire [9:0] vdp_cy = pal_line_hold ? 10'd623 : cy;
`else
  wire pal_line_hold = 1'b0;
  wire [9:0] vdp_cx = cx;
  wire [9:0] vdp_cy = cy;
`endif

  video vga (
    .clk(clk_vga),
    .reset(reset),
    .cx(vdp_cx),
    .cy(vdp_cy),
    .vga_r(red),
    .vga_g(green),
    .vga_b(blue),
    .vga_hs(hSync),
    .vga_vs(vSync),
    .raster_hc(raster_hc),
    .raster_vc(raster_vc),
    .vga_addr(vga_addr),
    .vga_din(cpuDataOut),
    .vga_dout(vga_dout),
    .vga_wr(vga_wr && cpuClockEdge),
    .vga_rd(vga_rd && cpuClockEdge),
    .mode(mode),
    .cpu_clk(cpuClock),
    .font_addr(font_addr),
    .name_table_addr(name_table_addr),
    .color_table_addr(color_table_addr),
    .sprite_attr_addr(sprite_attr_addr),
    .sprite_pattern_table_addr(sprite_pattern_table_addr),
    .n_int(n_int),
    .video_on(r_vdp[1][6]),
    .text_color(r_vdp[7][7:4]),
    .back_color(r_vdp[7][3:0]),
    .sprite_large(r_vdp[1][1]),
    .sprite_enlarged(r_vdp[1][0]),
    .vert_retrace_int(r_vdp[1][5]),
    .line_counter(line_counter),
    .line_int_en(r_vdp[0][4]),
    .status_read(status_read),
    .sprite_collision(sprite_collision),
    .too_many_sprites(too_many_sprites),
    .spritex(spritex),
    .interrupt_flag(interrupt_flag),
    .x_scroll(x_scroll),
    .y_scroll(y_scroll),
    .cram_selected(cram_selected),
    .disable_vert(r_vdp[0][7]),
    .disable_horiz(r_vdp[0][6]),
    .lines224(r_vdp[0][1] & r_vdp[1][4]),
    .lines240(r_vdp[0][1] & r_vdp[1][3]),
    .mask_col0(r_vdp[0][5]),
    // pal_mode: PAL bitstream, 312 SMS lines. European games such as
    // The Addams Family stream the player sprites and the top HUD
    // during blanking and do not finish in an NTSC frame, so the
    // raster samples a half-written SAT.
    .pal(pal_mode),
    .line_hold(pal_line_hold),
    .frame_height(frame_height),
    .v_counter(v_counter),
    .h_counter(h_counter),
    .diag(vga_diag)
  );

`ifdef SYNTHESIS

  // HDMI video and audio. cx/cy are the only raster counters.
  // NTSC matches video.v (800x524). PAL is CEA VIC 17 (864x625) and
  // frame_height_i stays 0 so the core uses that total.
  // The only reset is the power-up one (raster_rst), which also holds the
  // CPU divider, so the raster still free-runs with it afterwards.
`ifdef PAL
  localparam [11:0] HDMI_VIC = 12'd17;
  localparam HDMI_CLK_HZ = 27_000_000;
  localparam HDMI_FRAME_W = 864;
  localparam HDMI_FRAME_H = 625;
  localparam HDMI_SCREEN_W = 720;
  localparam HDMI_SCREEN_H = 576;
  localparam HDMI_HSYNC_START = 12;
  localparam HDMI_HSYNC_SIZE = 64;
  localparam HDMI_VSYNC_START = 5;
  localparam HDMI_VSYNC_SIZE = 5;
`else
  localparam [11:0] HDMI_VIC = 12'd0;
  localparam HDMI_CLK_HZ = 25_000_000;
  localparam HDMI_FRAME_W = 800;
  localparam HDMI_FRAME_H = 524;
  localparam HDMI_SCREEN_W = 640;
  localparam HDMI_SCREEN_H = 480;
  localparam HDMI_HSYNC_START = 16;
  localparam HDMI_HSYNC_SIZE = 96;
  localparam HDMI_VSYNC_START = 11;
  localparam HDMI_VSYNC_SIZE = 2;
`endif
  hdmi #(
    .VIDEO_ID_CODE(HDMI_VIC),
    .IT_CONTENT(1'b1),
    .DVI_OUTPUT(1'b0),
    .AUDIO_RATE(48000),
    .AUDIO_BIT_WIDTH(16),
    .FRAME_WIDTH(HDMI_FRAME_W),
    .FRAME_HEIGHT(HDMI_FRAME_H),
    .SCREEN_WIDTH(HDMI_SCREEN_W),
    .SCREEN_HEIGHT(HDMI_SCREEN_H),
    .HSYNC_PULSE_START(HDMI_HSYNC_START),
    .HSYNC_PULSE_SIZE(HDMI_HSYNC_SIZE),
    .VSYNC_PULSE_START(HDMI_VSYNC_START),
    .VSYNC_PULSE_SIZE(HDMI_VSYNC_SIZE),
    .INVERT_POLARITY(1),
    .TMDS_CLOCK_DDR(1),
    .TMDS_DIFFERENTIAL(1)
  ) u_hdmi (
    .clk_pixel_x5(clk_hdmi),
    .clk_pixel(clk_vga),
    .sample_strobe(sample_strobe),
    .reset(raster_rst),
    .rgb({hdmi_r, hdmi_g, hdmi_b}),
    .audio_sample_word_0(audio_sample),
    .audio_sample_word_1(audio_sample),
    .frame_height_i(12'd0),
    .tmds_p(gpdi_dp),
    .tmds_n(gpdi_dn),
    .cx(hdmi_cx),
    .cy(hdmi_cy)
  );

  hdmi_audio_clk_gen #(
    .CLK_HZ(HDMI_CLK_HZ),
    .AUDIO_HZ(48000)
  ) u_audio_clk (
    .clk_pixel(clk_vga),
    .reset(raster_rst),
    .sample_strobe(sample_strobe)
  );
`else // SYNTHESIS

    assign vga_hsync = hSync;
    assign vga_vsync = vSync;
    assign vga_r = red;
    assign vga_g = green;
    assign vga_b = blue;

`endif // SYNTHESIS

  // ===============================================================
  // MEMORY READ/WRITE LOGIC
  // ===============================================================

  assign n_ioWR  = n_WR | n_IORQ;
  assign n_memWR = n_WR | n_MREQ;
  assign n_ioRD  = n_RD | n_IORQ;
  assign n_memRD = n_RD | n_MREQ;

  // ===============================================================
  // Memory decoding
  // ===============================================================

  reg  r_interrupt_flag, r_sprite_collision;
  reg  r_status_read;
  reg  status_read;
  wire [7:0] status = {r_interrupt_flag, too_many_sprites, r_sprite_collision, (too_many_sprites ? spritex : 5'b11111)};
  // Active low. B is button 1, A is button 2, same as player 1.
  // $DC[7:6] is P2 Down/Up. $DD[3:0] is P2 button 2, button 1, Right, Left.
  // $DD[7:4] stays the TH/reset nibble.
  wire [7:0] joy_data0 = joypad2 ? {R_btn_joy[4:3], 6'b111111} : {~p2_joy[3], ~p2_joy[2], ~R_btn_joy[2:1], ~R_btn_joy[6:3]};
  wire [7:0] joy_data1 = joypad2 ? {4'b0101, R_btn_joy[2:1], R_btn_joy[6:5]} : {4'b1011, ~p2_joy[1], ~p2_joy[0], ~p2_joy[5], ~p2_joy[4]};

  assign cpuDataIn =  vdp_data_port && n_ioRD == 1'b0 ? vga_dout :
                      vdp_ctrl_port && n_ioRD == 1'b0 ? status :
		      // Controllers 0 and 1
		      joypad_0_port && n_ioRD == 1'b0 ? joy_data0 :
		      joypad_1_port && n_ioRD == 1'b0 ? joy_data1 :
                      // V and H counters
                      v_counter_port && n_ioRD == 1'b0 ? v_counter :
                      h_counter_port && n_ioRD == 1'b0 ? h_counter :
                      cpuAddress[15:14] < 3 && n_memRD == 1'b0 ?
                        (r_mem_ctrl[3] == 0 ? biosOut :
                         cart_ram_sel ? cartRamOut : romOut) : ramOut;

  // Sprite collision interrupt
  always @(posedge cpuClock) begin
    if (!n_hard_reset) begin
      r_interrupt_flag <= 0;
      r_sprite_collision <= 0;
      status_read <= 0;
    end else begin
      status_read <= 0;
      if (interrupt_flag) r_interrupt_flag <= 1;
      if (sprite_collision) r_sprite_collision <= 1;
      if (cpuClockEdge) begin
        r_status_read <= vdp_ctrl_port && n_ioRD == 1'b0;
        if (r_status_read && !(vdp_ctrl_port && n_ioRD == 1'b0)) begin
          r_interrupt_flag <= 0;
          r_sprite_collision <= 0;
          status_read <= 1;
        end
      end
    end
  end
  
  // ===============================================================
  // CPU clock
  // ===============================================================
  // An SMS line is exactly 228 T-states. Hang-On samples the V counter
  // from the line IRQ and indexes the road scroll by that value; a
  // walking phase moves the sample onto the next line and the curve
  // flickers. The enable stays high for the last 3 clocks of every
  // period, matching the duty cycle the PSG and SDRAM use.
  // NTSC: 228 edges in 1600 clocks. 56 periods of 7 plus one of 8
  // in every 400 clocks.
  // PAL: 228 edges in 1728 clocks (two 864-clock VIC 17 lines).
  // 19 T-states in 144 clocks is 11 periods of 8 and 8 of 7.
  // 1728 / 144 = 12, so 624 HDMI lines stay phase-locked. Line 624 holds.
  reg [2:0] cpuSub = 0;
  reg [5:0] cpuSlot = 0;
`ifdef PAL
  wire cpuLong = (cpuSlot < 6'd11);
  localparam [5:0] CPU_SLOT_LAST = 6'd18;
`else
  wire cpuLong = (cpuSlot == 6'd0);
  localparam [5:0] CPU_SLOT_LAST = 6'd56;
`endif
  wire [2:0] cpuLast = cpuLong ? 3'd7 : 3'd6;
  wire [2:0] cpuHighAt = cpuLong ? 3'd5 : 3'd4;

  always @(posedge cpuClock) begin
    cpuClockEnable1 <= cpuClockEnable;
    if (raster_rst) begin
      cpuSub <= 3'd0;
      cpuSlot <= 6'd0;
      cpuClockEnable <= 1'b0;
    end else if (pal_line_hold) begin
      cpuClockEnable <= 1'b0;
    end else if (cpuSub == cpuLast) begin
      cpuSub <= 3'd0;
      cpuClockEnable <= 1'b0;
      if (cpuSlot == CPU_SLOT_LAST)
        cpuSlot <= 6'd0;
      else
        cpuSlot <= cpuSlot + 6'd1;
    end else begin
      cpuSub <= cpuSub + 3'd1;
      cpuClockEnable <= ((cpuSub + 3'd1) >= cpuHighAt);
    end
  end

  // ===============================================================
  // Audio
  // ===============================================================
  wire [13:0] audio_dout;
  wire sound_ready;

  sn76489 #(14) sound (
    .clk(cpuClock),
    .clk_en(cpuClockEnable),
    .reset(!n_hard_reset),
    .ce_n(1'b0),
    .we_n(!(psg_write_port && n_ioWR == 1'b0)),
    .ready(sound_ready),
    .d(cpuDataOut),
    .audio_out(audio_dout)
  );

`ifdef SYNTHESIS
  // The PSG sample is unipolar and silent at 0. A leaky average removes
  // that DC so HDMI LPCM is signed. The PSG is mono, so both channels match.
  // Part-selects and concatenations are unsigned, so the signed wires
  // below restore the sign bit before the arithmetic.
  reg signed [23:0] audio_dc = 0;
  wire signed [15:0] audio_raw = {2'b0, audio_dout};
  wire signed [15:0] audio_dc_s = audio_dc[23:8];
  wire signed [23:0] audio_step = {{8{audio_sample[15]}}, audio_sample};
  assign audio_sample = audio_raw - audio_dc_s;

  always @(posedge clk_vga) begin
    if (sample_strobe)
      audio_dc <= audio_dc + audio_step;
  end
`endif

  // ===============================================================
  // Leds
  // ===============================================================
  // D4 (led[4]) is the video standard: on for PAL, off for NTSC.
  // led[5] is player 2 present (IcePi USB2). It stays off on ULX3S.
  assign led = {usb_type, |usb2_type, pal_mode, !n_hard_reset, mode};

  always @(posedge cpuClock) diag16 <= {r_vdp[0], r_vdp[1]};

endmodule
