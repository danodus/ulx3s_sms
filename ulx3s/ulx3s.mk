PIN_DEF ?= ulx3s_v20.lpf

DEVICE ?= 85k

# SPI flash layout. Power-up loads NTSC from address 0. Each image names
# the other one as its next boot address (ECP5 multiboot), so holding
# SELECT for 2 s, which pulls PROGRAMN low, swaps NTSC and PAL.
NTSC_FLASH_ADDR = 0x000000
PAL_FLASH_ADDR  = 0x200000

# PAL=1 builds VIC 17 (720x576p at 50 Hz, 27 MHz) into bin_pal/.
# The default is the NTSC raster, into bin/.
ifeq ($(PAL),1)
BUILDDIR = bin_pal
NEXTPNR_FREQ = 27
YOSYS_DEFS = verilog_defaults -add -DPAL;
BOOTADDR = $(NTSC_FLASH_ADDR)
else
BUILDDIR = bin
NEXTPNR_FREQ = 25
YOSYS_DEFS =
BOOTADDR = $(PAL_FLASH_ADDR)
endif

compile: $(BUILDDIR)/toplevel.bit

prog: $(BUILDDIR)/toplevel.bit
	fujprog $^

# Writes only this image, at its slot. The other slot must also be
# programmed for the SELECT switch to work; see flash-all.
flash: $(BUILDDIR)/toplevel.bit
ifeq ($(PAL),1)
	openFPGALoader -b ulx3s -f -o $(PAL_FLASH_ADDR) $<
else
	openFPGALoader -b ulx3s -f -o $(NTSC_FLASH_ADDR) $<
endif

# Builds NTSC and PAL and writes both. Replaces any bootloader at 0.
flash-all:
	$(MAKE) PAL=0 compile
	$(MAKE) PAL=1 compile
	openFPGALoader -b ulx3s -f -o $(NTSC_FLASH_ADDR) bin/toplevel.bit
	openFPGALoader -b ulx3s -f -o $(PAL_FLASH_ADDR) bin_pal/toplevel.bit

$(BUILDDIR)/toplevel.json: $(VERILOG) $(BUILDDIR)/firmware.hex $(BUILDDIR)/font8x8.hex
	mkdir -p $(BUILDDIR)
	yosys -p "$(YOSYS_DEFS) read_verilog -sv $(filter %.sv,$(VERILOG)); read_verilog $(filter %.v,$(VERILOG)); synth_ecp5 -top sms -json $@"

$(BUILDDIR)/%.config: $(PIN_DEF) $(BUILDDIR)/toplevel.json
	nextpnr-ecp5 --${DEVICE} --package CABGA381 --timing-allow-fail --freq $(NEXTPNR_FREQ) --textcfg  $@ --json $(filter-out $<,$^) --lpf $<

$(BUILDDIR)/toplevel.bit: $(BUILDDIR)/toplevel.config
	ecppack --compress --bootaddr $(BOOTADDR) $^ $@

clean:
	rm -rf bin bin_pal

.SECONDARY:
.PHONY: compile clean prog flash flash-all
