# Sega Master System for ULX3S and IcePi Zero ECP5 FPGAs

## Introduction

This is a version of the Sega Master System 8-bit games console for the ULX3S and IcePi Zero boards, written entirely in Verilog.

It has HDMI video and 48 kHz PSG audio, and optional VGA output. The resolution is 640x480. The pixel clock is 25 MHz. The headphone-jack DAC is not used.

Joypad 1 is implemented by using the buttons.

It currently uses the Europe/USA 1.3 BIOS, which, on power-up,  displays the Sega trademark and then looks for a game cartridge.

On power-up, and again after the power button is pressed, the Z80 stays in reset until a cartridge is loaded. You can load a game in either of these ways:

**SD card (recommended):** Format a microSD card as **FAT32** and copy `.sms` ROM files to the card. Files can be in the root or in folders, and long filenames are shown. Insert the card, power on (or press the power button to return to the menu). Use **Up/Down** (board buttons or either USB gamepad) to highlight an entry and **Fire1 / A** to open a folder or load a ROM. B does the same. In a folder, **..** is the first entry and goes up one level. A file list is shown on HDMI while the menu is active. Names longer than 96 characters are cut off.

**USB serial:** Transfer a ROM with:

```
python3 tools/load_rom.py /dev/cu.usbserial-XXXX roms/game.sms
```

The script needs pyserial (`python3 -m pip install pyserial`). It waits for the loader, sends the ROM at 921600 baud, and the game starts once the transfer checks out. Serial loading still works while the SD menu is shown. Press the power button to load a different ROM.

The SD menu firmware is built with a RISC-V GCC toolchain (`firmware/sdmenu/`). Set `RV_PREFIX` in `firmware/sdmenu/Makefile` if your `riscv-none-elf-gcc` is not in the default path.

## Implementation

It is written entirely in Verilog. The top level and VDP implementation are new.

The rom cartridge is loaded into the SDRAM and executed from there. `tools/load_rom.py` checks for a Codemasters header and tells the core which mapper to use; everything else uses the Sega mapper.

The NTSC bitstream generates a 640x480 raster at 25 MHz (800x524). The PAL bitstream is CEA VIC 17, 720x576p at 50 Hz with a 27 MHz pixel clock and an 864x625 frame. The VDP runs 312 SMS lines and holds the CPU on the last HDMI line so the 228 T-state line stays aligned. It does not use the timing of the original VDP chip. Legacy modes compatible with Texas Instruments TMS9918 chip are implemented for compatibility with the Sega SG 1000.

PSG audio is sent as signed 16-bit HDMI LPCM at 48 kHz, the same mono sample on both channels.

Console memory (8KB) uses BRAM, as does the video ram (16KB), and the bios rom (32KB).

## Installation

You need recent versions of Yosys, nextpnr-ecp5, project trellis and fujprog.

## ULX3S

```
source /path/to/oss-cad-suite/environment
cd ulx3s
make prog
```

This builds the RV32 SD menu firmware, then synthesizes the NTSC bitstream into `bin/`.

```
make PAL=1 prog
```

builds the PAL bitstream into `bin_pal/` and programs that instead. The two images are separate. SELECT does not switch between them.

It currently defaults to an 85F board.

## IcePi Zero

```
source /path/to/oss-cad-suite/environment
cd icepi_zero
make prog
```

`make flash` writes the bitstream to SPI flash. `make PAL=1 prog` and `make PAL=1 flash` do the same for the PAL image in `bin_pal/`.

## Gamepad Buttons

Press START on the USB gamepad while a game is running to pause. SELECT returns to the ROM menu. The video standard is whichever bitstream was programmed. D4 stays lit on the PAL image. The PAL pixel clock is 27 MHz; NTSC stays at 25 MHz.

## USB Gamepad

Press START on either gamepad while a game is running to pause. Press SELECT while a game is running to return to the SD card ROM menu. On IcePi Zero, controller 2 does the same. To run a European ROM, program the PAL bitstream (`make PAL=1 prog` or `make PAL=1 flash`).

## Bugs

Refer to the [compatibility list](COMPAT.md) for more details.
