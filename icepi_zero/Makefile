FIRMWARE_HEX = ../firmware/sdmenu/firmware.hex

VERILOG = icepi_zero_top.v \
	  ../src/sms.v ../src/ram.v ../src/vram.v ../src/rom.v \
	  ../src/Z80/tv80_core.v ../src/Z80/tv80n.v ../src/Z80/tv80_mcode.v \
	  ../src/Z80/tv80_reg.v ../src/Z80/tv80_alu.v \
	  ../src/video.v \
	  ../src/sn76489.v ../src/tone_generator.v \
	  ../third_party/ecp5_hdmi_audio_video/rtl/hdmi.v \
	  ../third_party/ecp5_hdmi_audio_video/rtl/hdmi_audio_clk_gen.v \
	  ../third_party/ecp5_hdmi_audio_video/rtl/hdmi_audio_clock_regeneration_packet.v \
	  ../third_party/ecp5_hdmi_audio_video/rtl/hdmi_audio_info_frame.v \
	  ../third_party/ecp5_hdmi_audio_video/rtl/hdmi_audio_sample_packet.v \
	  ../third_party/ecp5_hdmi_audio_video/rtl/hdmi_auxiliary_video_information_info_frame.v \
	  ../third_party/ecp5_hdmi_audio_video/rtl/hdmi_packet_assembler.v \
	  ../third_party/ecp5_hdmi_audio_video/rtl/hdmi_packet_picker.v \
	  ../third_party/ecp5_hdmi_audio_video/rtl/hdmi_serializer_ecp5.v \
	  ../third_party/ecp5_hdmi_audio_video/rtl/hdmi_source_product_description_info_frame.v \
	  ../third_party/ecp5_hdmi_audio_video/rtl/hdmi_tmds_channel.v \
	  ../src/lattice/ecp5pll.sv \
	  ../src/sdram.v \
	  ../src/serial_loader.v \
	  ../src/loader_cpu.v ../src/loader_soc.v ../src/sdram_card_loader.v ../src/loader_overlay.v \
	  ../third_party/FemtoRV/RTL/DEVICES/SDCard.v \
	  ../third_party/FemtoRV/RTL/DEVICES/Buttons.v \
	  ../src/usb_hid_host/usb_hid_host.v \
	  ../src/usb_hid_host/usb_hid_host_rom.v \
	  ../src/usb_hid_host/usb_pll.v \
	  ../src/usb_hid_host/usb_pll_12.v

PIN_DEF = icepi_zero.lpf
DEVICE ?= 25k
PACKAGE ?= CABGA256

# SPI flash layout. Power-up loads NTSC from address 0. Each image names
# the other one as its next boot address (ECP5 multiboot), so holding
# SELECT for 2 s, which pulls PROGRAMN low, swaps NTSC and PAL.
NTSC_FLASH_ADDR = 0x000000
PAL_FLASH_ADDR  = 0x200000

# REV14=1 wires the PROGRAMN pin (N12), which exists on IcePi Zero rev 1.4
# and later. On rev 1.2 and 1.3 N12 is another net, so it stays unused and
# the SELECT hold cannot reload the FPGA.
ifeq ($(REV14),1)
PIN_DEF += icepi_zero_rev14.lpf
EXTRA_DEFS = verilog_defaults -add -DPROGRAMN;
else
EXTRA_DEFS =
endif

# PAL=1 builds VIC 17 (720x576p at 50 Hz, 27 MHz) into bin_pal/.
# The default is the NTSC raster, into bin/.
ifeq ($(PAL),1)
BUILDDIR = bin_pal
NEXTPNR_FREQ = 27
YOSYS_DEFS = verilog_defaults -add -DICEPI; verilog_defaults -add -DPAL; $(EXTRA_DEFS)
BOOTADDR = $(NTSC_FLASH_ADDR)
else
BUILDDIR = bin
NEXTPNR_FREQ = 25
YOSYS_DEFS = verilog_defaults -add -DICEPI; $(EXTRA_DEFS)
BOOTADDR = $(PAL_FLASH_ADDR)
endif

OFL = openFPGALoader -c ft231X --pins=7:3:5:6

compile: $(BUILDDIR)/toplevel.bit

prog: $(BUILDDIR)/toplevel.bit
	$(OFL) $<

# Writes only this image, at its slot. The other slot must also be
# programmed for the SELECT switch to work; see flash-all.
flash: $(BUILDDIR)/toplevel.bit
ifeq ($(PAL),1)
	$(OFL) --write-flash -o $(PAL_FLASH_ADDR) $<
else
	$(OFL) --write-flash -o $(NTSC_FLASH_ADDR) $<
endif

# Builds NTSC and PAL and writes both.
flash-all:
	$(MAKE) PAL=0 compile
	$(MAKE) PAL=1 compile
	$(OFL) --write-flash -o $(NTSC_FLASH_ADDR) bin/toplevel.bit
	$(OFL) --write-flash -o $(PAL_FLASH_ADDR) bin_pal/toplevel.bit

FWDIR = ../firmware/sdmenu
FW_DEPS := $(FWDIR)/Makefile $(FWDIR)/ram.ld $(FWDIR)/crt0.S \
	$(FWDIR)/main.c $(FWDIR)/microwait.c $(FWDIR)/spi_sd.c \
	$(FWDIR)/io.h $(FWDIR)/fat_custom.h \
	$(wildcard $(FWDIR)/fat_io_lib/*.c $(FWDIR)/fat_io_lib/*.h)

$(FIRMWARE_HEX): $(FW_DEPS)
	$(MAKE) -C $(FWDIR)

$(BUILDDIR)/firmware.hex: $(FIRMWARE_HEX)
	mkdir -p $(BUILDDIR)
	cp $(FIRMWARE_HEX) $(BUILDDIR)/firmware.hex

FONT_HEX = ../src/font8x8.hex

$(BUILDDIR)/font8x8.hex: $(FONT_HEX)
	mkdir -p $(BUILDDIR)
	cp $(FONT_HEX) $(BUILDDIR)/font8x8.hex

$(BUILDDIR)/toplevel.json: $(VERILOG) $(BUILDDIR)/firmware.hex $(BUILDDIR)/font8x8.hex
	mkdir -p $(BUILDDIR)
	yosys -p "$(YOSYS_DEFS) read_verilog -sv $(filter %.sv,$(VERILOG)); read_verilog $(filter %.v,$(VERILOG)); synth_ecp5 -top icepi_zero_top -json $@"

$(BUILDDIR)/toplevel.config: $(PIN_DEF) $(BUILDDIR)/toplevel.json
	nextpnr-ecp5 --$(DEVICE) --package $(PACKAGE) --speed 6 --timing-allow-fail --freq $(NEXTPNR_FREQ) --textcfg $@ --json $(BUILDDIR)/toplevel.json $(addprefix --lpf ,$(PIN_DEF))

$(BUILDDIR)/toplevel.bit: $(BUILDDIR)/toplevel.config
	ecppack --compress --bootaddr $(BOOTADDR) $< $@

clean:
	rm -rf bin bin_pal

.SECONDARY:
.PHONY: compile clean prog flash flash-all
