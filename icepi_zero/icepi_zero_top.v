`default_nettype none
// IcePi Zero rev 1.2. The 50 MHz oscillator is the PLL reference.
// Pixel, CPU, and PSG clocks stay 25 MHz inside sms.
module icepi_zero_top
(
  input         clk,

  // Button 0, active low. Returns to the ROM menu.
  input         button,

  output [3:0]  gpdi_dp,
  output [3:0]  gpdi_dn,

  // First USB host socket (USB1). Not the Flash/UART jack.
  inout         usb_dn,
  inout         usb_dp,
  output        usb_pull_dp,
  output        usb_pull_dn,

  // On-board USB-UART. FPGA TX is uart_tx.
  input         uart_rx,
  output        uart_tx,

  inout         sd_clk,
  inout         sd_cmd,
  inout  [3:0]  sd_d,

  output        sdram_csn,
  output        sdram_clk,
  output        sdram_cke,
  output        sdram_rasn,
  output        sdram_casn,
  output        sdram_wen,
  output [12:0] sdram_a,
  output  [1:0] sdram_ba,
  output  [1:0] sdram_dqm,
  inout  [15:0] sdram_d,

  output [4:0]  led
);

  wire [27:0] gp_unused, gn_unused;
  wire [7:0] sms_led;

  // sms does not drive CKE. Hold the chip enabled.
  assign sdram_cke = 1'b1;

  // led[0] device present, [2:1] usb typ, [3] PAL, [4] held in reset.
  assign led = {sms_led[3], sms_led[4], sms_led[7], sms_led[6], |sms_led[7:6]};

  sms #(
    .c_clk_in_hz(50_000_000),
    .c_vga_out(0),
    .c_diag(0),
    .c_lcd_hex(0)
  ) u_sms (
    .clk_25mhz(clk),
    .btn({6'b0, button}),
    .sw(4'b0),
    .gpdi_dp(gpdi_dp),
    .gpdi_dn(gpdi_dn),
    .usb_fpga_bd_dn(usb_dn),
    .usb_fpga_bd_dp(usb_dp),
    .usb_fpga_pu_dp(usb_pull_dp),
    .usb_fpga_pu_dn(usb_pull_dn),
    .ftdi_txd(uart_rx),
    .ftdi_rxd(uart_tx),
    .wifi_txd(1'b1),
    .wifi_gpio16(1'b1),
    .wifi_gpio5(1'b1),
    .sd_clk(sd_clk),
    .sd_cmd(sd_cmd),
    .sd_d(sd_d),
    .sdram_csn(sdram_csn),
    .sdram_clk(sdram_clk),
    .sdram_rasn(sdram_rasn),
    .sdram_casn(sdram_casn),
    .sdram_wen(sdram_wen),
    .sdram_a(sdram_a),
    .sdram_ba(sdram_ba),
    .sdram_dqm(sdram_dqm),
    .sdram_d(sdram_d),
    .gp(gp_unused),
    .gn(gn_unused),
    .led(sms_led)
  );

endmodule
`default_nettype wire
