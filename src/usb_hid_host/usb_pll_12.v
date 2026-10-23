// 100 MHz -> 12 MHz in one ECP5 PLL.
// f_pfd = 100/25 = 4 MHz, f_out = f_pfd * 3 = 12 MHz, VCO = 12*50 = 600 MHz.
// Exact 12 MHz from the IcePi 50 MHz oscillator is outside the PFD range,
// so this stage takes the 100 MHz SDRAM clock instead of usb_pll's two PLLs.

module usb_pll_12
(
    input  clkin,   // 100 MHz
    input  rst,     // hold until clkin is stable
    output clk12,   // 12 MHz
    output locked
);

(* FREQUENCY_PIN_CLKI="100" *)
(* FREQUENCY_PIN_CLKOP="12" *)
(* ICP_CURRENT="12" *) (* LPF_RESISTOR="8" *) (* MFG_ENABLE_FILTEROPAMP="1" *) (* MFG_GMCREF_SEL="2" *)
EHXPLLL #(
        .PLLRST_ENA("ENABLED"),
        .INTFB_WAKE("DISABLED"),
        .STDBY_ENABLE("DISABLED"),
        .DPHASE_SOURCE("DISABLED"),
        .OUTDIVIDER_MUXA("DIVA"),
        .OUTDIVIDER_MUXB("DIVB"),
        .OUTDIVIDER_MUXC("DIVC"),
        .OUTDIVIDER_MUXD("DIVD"),
        .CLKI_DIV(25),
        .CLKOP_ENABLE("ENABLED"),
        .CLKOP_DIV(50),
        .CLKOP_CPHASE(24),
        .CLKOP_FPHASE(0),
        .FEEDBK_PATH("CLKOP"),
        .CLKFB_DIV(3)
    ) pll_i (
        .RST(rst),
        .STDBY(1'b0),
        .CLKI(clkin),
        .CLKOP(clk12),
        .CLKFB(clk12),
        .CLKINTFB(),
        .PHASESEL0(1'b0),
        .PHASESEL1(1'b0),
        .PHASEDIR(1'b1),
        .PHASESTEP(1'b1),
        .PHASELOADREG(1'b1),
        .PLLWAKESYNC(1'b0),
        .ENCLKOP(1'b0),
        .LOCK(locked)
	);

endmodule
