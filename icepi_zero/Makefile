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
BUILDDIR = bin

compile: $(BUILDDIR)/toplevel.bit

prog: $(BUILDDIR)/toplevel.bit
	openFPGALoader -c ft231X --pins=7:3:5:6 $<

flash: $(BUILDDIR)/toplevel.bit
	openFPGALoader -c ft231X --pins=7:3:5:6 $< --write-flash

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
	yosys -p "synth_ecp5 -top icepi_zero_top -json $@" $(VERILOG)

$(BUILDDIR)/toplevel.config: $(PIN_DEF) $(BUILDDIR)/toplevel.json
	nextpnr-ecp5 --$(DEVICE) --package $(PACKAGE) --speed 6 --timing-allow-fail --freq 25 --textcfg $@ --json $(filter-out $<,$^) --lpf $<

$(BUILDDIR)/toplevel.bit: $(BUILDDIR)/toplevel.config
	ecppack --compress $< $@

clean:
	rm -rf $(BUILDDIR)

.SECONDARY:
.PHONY: compile clean prog flash
