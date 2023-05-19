module top (
    input        clk,
    output [7:0] display_o,

    input [6:0]  btn,

    output       vga_hsync,
    output       vga_vsync,
    output [7:0] vga_r,
    output [7:0] vga_g,
    output [7:0] vga_b,
    );

    sms sms
    (
        .clk_25mhz(clk),

        // Buttons
        .btn(btn),

        .vga_hsync,
        .vga_vsync,
        .vga_r,
        .vga_g,
        .vga_b,  

        // Leds
        .led(display_o)
    );
  
    
endmodule