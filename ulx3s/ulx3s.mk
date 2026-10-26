PIN_DEF ?= ulx3s_v20.lpf

DEVICE ?= 85k

# PAL=1 builds VIC 17 (720x576p at 50 Hz, 27 MHz) into bin_pal/.
# The default is the NTSC raster, into bin/.
ifeq ($(PAL),1)
BUILDDIR = bin_pal
NEXTPNR_FREQ = 27
YOSYS_DEFS = verilog_defaults -add -DPAL;
else
BUILDDIR = bin
NEXTPNR_FREQ = 25
YOSYS_DEFS =
endif

compile: $(BUILDDIR)/toplevel.bit

prog: $(BUILDDIR)/toplevel.bit
	fujprog $^

$(BUILDDIR)/toplevel.json: $(VERILOG) $(BUILDDIR)/firmware.hex $(BUILDDIR)/font8x8.hex
	mkdir -p $(BUILDDIR)
	yosys -p "$(YOSYS_DEFS) read_verilog -sv $(filter %.sv,$(VERILOG)); read_verilog $(filter %.v,$(VERILOG)); synth_ecp5 -top sms -json $@"

$(BUILDDIR)/%.config: $(PIN_DEF) $(BUILDDIR)/toplevel.json
	nextpnr-ecp5 --${DEVICE} --package CABGA381 --timing-allow-fail --freq $(NEXTPNR_FREQ) --textcfg  $@ --json $(filter-out $<,$^) --lpf $<

$(BUILDDIR)/toplevel.bit: $(BUILDDIR)/toplevel.config
	ecppack --compress $^ $@

clean:
	rm -rf bin bin_pal

.SECONDARY:
.PHONY: compile clean prog
