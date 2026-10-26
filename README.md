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

builds the PAL bitstream into `bin_pal/` and programs that instead. `prog` loads SRAM only, so power cycling returns to whatever is in flash.

```
make flash-all
```

builds both images and writes NTSC to SPI flash at `0x000000` and PAL at `0x200000` (using `openFPGALoader -b ulx3s`). This replaces a bootloader at address 0, if one is installed. Each image is built with `ecppack --bootaddr` naming the other as the next boot (ECP5 multiboot). Hold SELECT on a gamepad for 2 seconds, in a game or in the menu, to pull `user_programn` low. The FPGA then reloads the other image, so you switch between NTSC and PAL. Power-up always starts in NTSC. A short SELECT press still returns to the ROM menu. `make flash` and `make PAL=1 flash` write a single slot.

It currently defaults to an 85F board. The reload needs `user_programn` on ULX3S PCB v2.0.5 or later.

## IcePi Zero

```
source /path/to/oss-cad-suite/environment
cd icepi_zero
make prog
```

`make flash` writes the NTSC bitstream to SPI flash at `0x000000`. `make PAL=1 prog` loads the PAL image from `bin_pal/`, and `make PAL=1 flash` writes it at `0x200000`. `make flash-all` builds and writes both.

Holding SELECT for 2 seconds reloads the other image from flash (multiboot, as on ULX3S), but it needs the `PROGRAMN` pin, which only IcePi Zero rev 1.4 and later route to the FPGA (N12). Build with `REV14=1` (for example `make REV14=1 flash-all`) on those boards. On rev 1.2 and 1.3 the hold does nothing; program the image you want with `make prog` / `make PAL=1 prog`, or power cycle to return to NTSC.

## Gamepad Buttons

Press START on the USB gamepad while a game is running to pause. A short SELECT press returns to the ROM menu. Holding SELECT for 2 seconds switches between the NTSC and PAL bitstreams in flash. The video standard is whichever bitstream is loaded. D4 stays lit on the PAL image. The PAL pixel clock is 27 MHz; NTSC stays at 25 MHz.

## USB Gamepad

Press START on either gamepad while a game is running to pause. Press SELECT while a game is running to return to the SD card ROM menu. On IcePi Zero, controller 2 does the same. To run a European ROM, hold SELECT for 2 seconds to switch to the PAL bitstream (after `make flash-all`), or program it directly (`make PAL=1 prog`).

## Bugs

Refer to the [compatibility list](COMPAT.md) for more details.
