RV_PREFIX ?= /Users/dcliche/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-
CC      = $(RV_PREFIX)gcc
OBJCOPY = $(RV_PREFIX)objcopy

ARCH  = rv32i
ABI   = ilp32
OPT   = -Os

CFLAGS = -march=$(ARCH) -mabi=$(ABI) $(OPT) -ffunction-sections -fdata-sections \
         -DFATFS_USE_CUSTOM_OPTS_FILE -I. -Wall -Wextra
LDFLAGS = -T ram.ld -nostartfiles -Wl,--gc-sections -lc -lgcc

FAT_SRCS = fat_io_lib/fat_access.c fat_io_lib/fat_cache.c fat_io_lib/fat_filelib.c \
           fat_io_lib/fat_misc.c fat_io_lib/fat_string.c fat_io_lib/fat_table.c

SRCS = crt0.S main.c microwait.c spi_sd.c $(FAT_SRCS)

OBJS = $(SRCS:.c=.o)
OBJS := $(OBJS:.S=.o)

HDRS = io.h fat_custom.h

all: firmware.hex

firmware.elf: $(OBJS) ram.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(OBJS) -lgcc

# $readmemh into the 32-bit CPU RAM takes one word per line.
# objcopy -O verilog emits bytes, which Yosys then stores as separate words.
firmware.hex: firmware.elf
	$(OBJCOPY) -O binary $< firmware.bin
	python3 -c 'd=open("firmware.bin","rb").read(); \
open("firmware.hex","w").write("".join("%08x\n" % ( \
  d[i] | ((d[i+1] if i+1 < len(d) else 0) << 8) | \
  ((d[i+2] if i+2 < len(d) else 0) << 16) | \
  ((d[i+3] if i+3 < len(d) else 0) << 24)) \
  for i in range(0, len(d), 4)))'

%.o: %.c $(HDRS)
	$(CC) $(CFLAGS) -c -o $@ $<

%.o: %.S
	$(CC) $(CFLAGS) -c -o $@ $<

clean:
	rm -f $(OBJS) firmware.elf firmware.hex firmware.bin

.PHONY: all clean
