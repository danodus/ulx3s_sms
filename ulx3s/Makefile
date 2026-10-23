FIRMWARE_HEX = ../firmware/sdmenu/firmware.hex

VERILOG = ../src/sms.v ../src/ram.v ../src/vram.v ../src/rom.v \
	  ../src/Z80/tv80_core.v ../src/Z80/tv80n.v ../src/Z80/tv80_mcode.v \
	  ../src/Z80/tv80_reg.v ../src/Z80/tv80_alu.v \
	  ../src/video.v ../src/hdmi.v \
	  ../src/sn76489.v ../src/tone_generator.v ../src/sigmadelta.v\
	  ../src/lattice/ecp5pll.sv \
	  ../src/sdram.v \
	  ../src/serial_loader.v \
	  ../src/loader_cpu.v ../src/loader_soc.v ../src/sdram_card_loader.v ../src/loader_overlay.v \
	  ../third_party/FemtoRV/RTL/DEVICES/SDCard.v \
	  ../third_party/FemtoRV/RTL/DEVICES/Buttons.v \
	  ../src/usb_hid_host/usb_hid_host.v \
	  ../src/usb_hid_host/usb_hid_host_rom.v \
	  ../src/usb_hid_host/usb_pll.v

PIN_DEF = ulx3s_v20.lpf

include ulx3s.mk

$(FIRMWARE_HEX):
	$(MAKE) -C ../firmware/sdmenu

$(BUILDDIR)/firmware.hex: $(FIRMWARE_HEX)
	mkdir -p $(BUILDDIR)
	cp $(FIRMWARE_HEX) $(BUILDDIR)/firmware.hex

FONT_HEX = ../src/font8x8.hex

$(BUILDDIR)/font8x8.hex: $(FONT_HEX)
	mkdir -p $(BUILDDIR)
	cp $(FONT_HEX) $(BUILDDIR)/font8x8.hex

