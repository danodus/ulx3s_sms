FIRMWARE_HEX = ../firmware/sdmenu/firmware.hex

VERILOG = ../src/sms.v ../src/ram.v ../src/vram.v ../src/rom.v \
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

PIN_DEF = ulx3s_v20.lpf

include ulx3s.mk

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

