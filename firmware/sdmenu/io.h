#ifndef SDMENU_IO_H
#define SDMENU_IO_H

#include <stdint.h>

#define IO_BASE 0x400000u

#define IO_BIT_TO_OFFSET(io_bit) (1u << (2u + (io_bit)))

#define IO_SDCARD_bit     8
#define IO_BUTTONS_bit    9
#define IO_OVERLAY_bit    12
#define IO_SDRAM_BYTE_bit 13
#define IO_SDRAM_CTL_bit  14
#define IO_SDRAM_LEN_bit  15

#define IO_SDCARD      IO_BIT_TO_OFFSET(IO_SDCARD_bit)
#define IO_BUTTONS     IO_BIT_TO_OFFSET(IO_BUTTONS_bit)
#define IO_OVERLAY     IO_BIT_TO_OFFSET(IO_OVERLAY_bit)
#define IO_SDRAM_BYTE  IO_BIT_TO_OFFSET(IO_SDRAM_BYTE_bit)
#define IO_SDRAM_CTL   IO_BIT_TO_OFFSET(IO_SDRAM_CTL_bit)
#define IO_SDRAM_LEN   IO_BIT_TO_OFFSET(IO_SDRAM_LEN_bit)

#define IO_IN(port)       (*(volatile uint32_t *)(IO_BASE + (port)))
#define IO_OUT(port, val) (*(volatile uint32_t *)(IO_BASE + (port)) = (val))

/* Menu text buffer in CPU RAM; HDMI overlay reads the same words. */
#define MENU_FB_BASE 0x00020000u
#define MENU_FB      ((volatile char *)MENU_FB_BASE)

#define OVERLAY_CHAR_BIT 25u
#define OVERLAY_SEL_BIT  24u

#define BTN_UP    (1u << 5)
#define BTN_DOWN  (1u << 4)
#define BTN_FIRE  (1u << 3)
#define BTN_PAD_U (1u << 2)
#define BTN_PAD_D (1u << 1)
#define BTN_PAD_A (1u << 0)

static inline void overlay_put(uint8_t row, uint8_t col, char c)
{
  uint32_t idx = (uint32_t)row * 40u + (uint32_t)col;
  MENU_FB[idx] = c;
  IO_OUT(IO_OVERLAY, (1u << OVERLAY_CHAR_BIT) | (idx << 8) | (uint8_t)c);
}

static inline void overlay_set_sel(uint8_t row)
{
  IO_OUT(IO_OVERLAY, (1u << OVERLAY_SEL_BIT) | ((uint32_t)row << 16));
}

static inline void sdram_write_byte(uint8_t b)
{
  IO_OUT(IO_SDRAM_BYTE, b);
}

static inline void sdram_set_mapper(int codemasters)
{
  IO_OUT(IO_SDRAM_CTL, codemasters ? 1u : 0u);
}

static inline void sdram_set_length(uint32_t len)
{
  IO_OUT(IO_SDRAM_LEN, len);
}

static inline void sdram_finalize(void)
{
  IO_OUT(IO_SDRAM_CTL, 2u);
}

#endif
