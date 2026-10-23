# Sega Master System for Ulx3s ECP5 FPGA

## Introduction

This is a version of the Sega Master System 8-bit games console for the Ulx3s board, written entirely in Verilog.

It has HDMI video and 48 kHz PSG audio, and optional VGA output. The resolution is 640x480. The pixel clock is 25 MHz. The headphone-jack DAC is not used.

Joypad 1 is implemented by using the buttons.

It currently uses the Europe/USA 1.3 BIOS, which, on power-up,  displays the Sega trademark and then looks for a game cartridge.

On power-up, and again after the power button is pressed, the Z80 stays in reset until a cartridge is loaded. You can load a game in either of these ways:

**SD card (recommended):** Format a microSD card as **FAT32** and copy `.sms` ROM files to the card. Files can be in the root or in folders, and long filenames are shown. Insert the card, power on (or press the power button to return to the menu). Use **Up/Down** (board buttons or USB gamepad) to highlight an entry and **Fire1 / A** to open a folder or load a ROM. In a folder, **..** is the first entry and goes up one level. A file list is shown on HDMI while the menu is active.

**USB serial:** Transfer a ROM with:

```
python3 tools/load_rom.py /dev/cu.usbserial-XXXX roms/game.sms
```

The script needs pyserial (`python3 -m pip install pyserial`). It waits for the loader, sends the ROM at 921600 baud, and the game starts once the transfer checks out. Serial loading still works while the SD menu is shown. Press the power button to load a different ROM.

The SD menu firmware is built with a RISC-V GCC toolchain (`firmware/sdmenu/`). Set `RV_PREFIX` in `firmware/sdmenu/Makefile` if your `riscv-none-elf-gcc` is not in the default path.

There are lots of games on the [planetemu](https://www.planetemu.net/roms/sega-master-system) site.

## Implementation

It is written entirely in Verilog. The top level and VDP implementation are new.

The rom cartridge is loaded into the SDRAM and executed from there. `tools/load_rom.py` checks for a Codemasters header and tells the core which mapper to use; everything else uses the Sega mapper.

The VDP implementation generates a 640x480 raster. HDMI timing comes from that raster, including the SW1 PAL frame (626 lines instead of 524). It does not use the timing of the original VDP chip. Legacy modes compatible with Texas Instruments TMS9918 chip are implemented for compatibility with the Sega SG 1000.

PSG audio is sent as signed 16-bit HDMI LPCM at 48 kHz, the same mono sample on both channels.

Console memory (8KB) uses BRAM, as does the video ram (16KB), and the bios rom (32KB).

## Installation

You need recent versions of Yosys, nextpnr-ecp5, project trellis and fujprog.

To build do (source the OSS CAD Suite first if yosys/nextpnr are not on your PATH):

```
source ~/oss-cad-suite/environment
cd ulx3s
make prog
```

This builds the RV32 SD menu firmware, then synthesizes the bitstream.

It currently defaults to an 85F board. To use a 12F add `DEVICE = 12k` to the Makefile.

You can select the PAL mode with SW1. OFF=NTSC (262 lines), ON=PAL (313 lines). Note that the unlike the real hardware the CPU clock speed is the same for both.

## USB Gamepad

A USB gamepad can be connected to US2 using a USB-OTG adapter.  When detected, both D6 and D7 LEDs will be ON.  With my Kiwitata SNES controller, the detection is not reliable.  This is a known issue with the USB HID host I'm using (https://github.com/nand2mario/usb_hid_host/issues/5).

Press Select on the gamepad while a game is running to return to the SD card ROM menu.

## Bugs

Pause NMI is not currently implemented.

Refer to the [compatibility list](COMPAT.md) for more details.
