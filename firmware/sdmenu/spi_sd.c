// Inspirations from:
// https://stackoverflow.com/questions/5048450/c-initializing-an-sd-card-in-spi-mode-always-reads-back-0xff (bit-banging)
// https://github.com/ultraembedded/minispartan6-audio/tree/master/src_c/drivers (clean low level driver and FAT access)
// http://www.dejazzer.com/ee379/lecture_notes/lec12_sd_card.pdf (info on SDCards and FAT filesystem)

#include "io.h"

void microwait(int us);
#define delay(ms) do { for (int _i = 0; _i < (ms); _i++) microwait(1000); } while (0)

// For now, does software bitbanging.
// TODO: a hardware shift register, will be cleaner...

#define MOSI_MASK 1
#define CLK_MASK  2
#define CSN_MASK  4

int spi_state = CSN_MASK;
/* Slow clock only while the card is still in its idle handshake. */
static int spi_slow = 1;

static inline void CS_H() {
    spi_state |= CSN_MASK;
    IO_OUT(IO_SDCARD, spi_state);    
}

static inline void CS_L() {
    spi_state &= ~CSN_MASK;
    IO_OUT(IO_SDCARD, spi_state);    
}

static inline void CK_H() {
    spi_state |= CLK_MASK;
    IO_OUT(IO_SDCARD, spi_state);    
}

static inline void CK_L() {
    spi_state &= ~CLK_MASK;
    IO_OUT(IO_SDCARD, spi_state);    
}

static inline void MOSI_H() {
    spi_state |= MOSI_MASK;
    IO_OUT(IO_SDCARD, spi_state);    
}

static inline void MOSI_L() {
    spi_state &= ~MOSI_MASK;
    IO_OUT(IO_SDCARD, spi_state);    
}

static inline int MISO() {
    return IO_IN(IO_SDCARD);
}

static inline void CLK_DELAY(void)
{
  /* Idle handshake must stay under 400 kHz. Reads run at the bit-bang rate. */
  if (spi_slow)
    microwait(2);
}

static inline void DLY_US(int t) {
  microwait(t); 
}

void spi_send (uint8_t d) {
    if (d & 0x80) MOSI_H(); else MOSI_L();    // bit7 
    CK_H(); CLK_DELAY(); CK_L(); CLK_DELAY();
    if (d & 0x40) MOSI_H(); else MOSI_L();    // bit6 
    CK_H(); CLK_DELAY(); CK_L(); CLK_DELAY();
    if (d & 0x20) MOSI_H(); else MOSI_L();    // bit5 
    CK_H(); CLK_DELAY(); CK_L(); CLK_DELAY();
    if (d & 0x10) MOSI_H(); else MOSI_L();    // bit4 
    CK_H(); CLK_DELAY(); CK_L(); CLK_DELAY();
    if (d & 0x08) MOSI_H(); else MOSI_L();    // bit3 
    CK_H(); CLK_DELAY(); CK_L(); CLK_DELAY();
    if (d & 0x04) MOSI_H(); else MOSI_L();    // bit2 
    CK_H(); CLK_DELAY(); CK_L(); CLK_DELAY();
    if (d & 0x02) MOSI_H(); else MOSI_L();    // bit1 
    CK_H(); CLK_DELAY(); CK_L(); CLK_DELAY();
    if (d & 0x01) MOSI_H(); else MOSI_L();    // bit0 
    CK_H(); CLK_DELAY(); CK_L(); CLK_DELAY();
}

uint8_t spi_receive () {
    uint8_t r;
    MOSI_H();    // Send 0xFF while receiving 
    r = 0;   if (MISO()) r++;    // bit7 
    CK_H(); CLK_DELAY(); CK_L(); CLK_DELAY();
    r <<= 1; if (MISO()) r++;    // bit6 
    CK_H(); CLK_DELAY(); CK_L(); CLK_DELAY();
    r <<= 1; if (MISO()) r++;    // bit5 
    CK_H(); CLK_DELAY(); CK_L(); CLK_DELAY();
    r <<= 1; if (MISO()) r++;    // bit4 
    CK_H(); CLK_DELAY(); CK_L(); CLK_DELAY();
    r <<= 1; if (MISO()) r++;    // bit3 
    CK_H(); CLK_DELAY(); CK_L(); CLK_DELAY();
    r <<= 1; if (MISO()) r++;    // bit2 
    CK_H(); CLK_DELAY(); CK_L(); CLK_DELAY();
    r <<= 1; if (MISO()) r++;    // bit1 
    CK_H(); CLK_DELAY(); CK_L(); CLK_DELAY();
    r <<= 1; if (MISO()) r++;    // bit0 
    CK_H(); CLK_DELAY(); CK_L(); CLK_DELAY();
    return r;
}

uint8_t spi_sendrecv(uint8_t cmd) {
    spi_send(cmd);
    return spi_receive();
}

void spi_readblock(uint8_t *ptr, int length) {
    int i;
    for (i=0;i<length;i++) {
        *ptr++ = spi_receive();
    }
}
 
void spi_writeblock(uint8_t *ptr, int length) {
    int i;
    for (i=0;i<length;i++) {
        spi_send(*ptr++);
    }
}


#define CMD0_GO_IDLE_STATE              0
#define CMD1_SEND_OP_COND               1
#define CMD8_SEND_IF_COND               8
#define CMD17_READ_SINGLE_BLOCK         17
#define CMD24_WRITE_SINGLE_BLOCK        24
#define CMD32_ERASE_WR_BLK_START        32
#define CMD33_ERASE_WR_BLK_END          33
#define CMD38_ERASE                     38
#define ACMD41_SD_SEND_OP_COND          41
#define CMD55_APP_CMD                   55
#define CMD58_READ_OCR                  58

#define CMD_START_BITS                  0x40
#define CMD0_CRC                        0x95
#define CMD8_CRC                        0x87

#define OCR_SHDC_FLAG                   0x40
#define CMD_OK                          0x01

#define CMD8_3V3_MODE_ARG               0x1AA

#define ACMD41_HOST_SUPPORTS_SDHC       0x40000000

#define CMD_START_OF_BLOCK              0xFE
#define CMD_DATA_ACCEPTED               0x05

static int sdhc_card = 0;

uint8_t sd_send_command(uint8_t cmd, uint32_t arg) {
    uint8_t response = 0xFF;
    uint8_t status;

    // If non-SDHC card, use byte addressing rather than block (512) addressing
    if(!sdhc_card) {
        switch (cmd) {
            case CMD17_READ_SINGLE_BLOCK:
            case CMD24_WRITE_SINGLE_BLOCK:
            case CMD32_ERASE_WR_BLK_START:
            case CMD33_ERASE_WR_BLK_END:
		arg *= 512;
		break;
        }
    }
    
    spi_send(cmd | CMD_START_BITS);
    spi_send((arg >> 24));
    spi_send((arg >> 16));
    spi_send((arg >> 8));
    spi_send((arg >> 0));

    // CRC required for CMD8 (0x87) & CMD0 (0x95) - default to CMD0
    spi_send((cmd == CMD8_SEND_IF_COND) ? CMD8_CRC : CMD0_CRC);

    /* NCR is 1..8 bytes. A missing card used to spin for hundreds of bytes. */
    int count = 0;
    while ((response = spi_receive()) == 0xff) {
        if (++count > 16)
            break;
    }

    // CMD58 has a R3 response
    if(cmd == CMD58_READ_OCR && response == 0x00) {
        // Check for SDHC card
        status = spi_receive();
        if(status & OCR_SHDC_FLAG) {
            sdhc_card = 1;
	} else {
            sdhc_card = 0;
	}

        // Ignore other response bytes for now
        spi_receive();
        spi_receive();
        spi_receive();
    }

    /* CMD8 returns R7 (4 bytes) after R1. Leaving them queued makes the
       next command look like a failure on some cards, especially after reset. */
    if (cmd == CMD8_SEND_IF_COND && response == CMD_OK) {
        spi_receive();
        spi_receive();
        spi_receive();
        if (spi_receive() != 0xAA)
            response = 0xff;
    }

    // Additional 8 clock cycles over SPI
    spi_send(0xFF);

    return response;
}

static void sd_clocks(int n)
{
    MOSI_H();
    while (n-- > 0) {
        CK_H();
        CLK_DELAY();
        CK_L();
        CLK_DELAY();
    }
}

static void sd_force_idle(void)
{
    /* Software state and the pin register can disagree after a CPU reset. */
    spi_state = CSN_MASK | MOSI_MASK;
    IO_OUT(IO_SDCARD, spi_state);
    sd_clocks(80);
}

int _sd_init(void)
{
    uint8_t response;
    int sd_version = 2;
    int i;

    spi_slow = 1;
    sd_force_idle();

    CS_L();
    DLY_US(50);
    response = 0xff;
    for (i = 0; i < 32; i++) {
        response = sd_send_command(CMD0_GO_IDLE_STATE, 0);
        if (response == CMD_OK)
            break;
    }
    if (response != CMD_OK) {
        sd_force_idle();
        return -1;
    }

    response = sd_send_command(CMD8_SEND_IF_COND, CMD8_3V3_MODE_ARG);
    if (response != CMD_OK) {
        sd_version = 1;
        sdhc_card = 0;
    }

    response = 0xff;
    for (i = 0; i < 100; i++) {
        sd_send_command(CMD55_APP_CMD, 0);
        response = sd_send_command(ACMD41_SD_SEND_OP_COND,
            sd_version == 2 ? ACMD41_HOST_SUPPORTS_SDHC : 0);
        if (response == 0x00)
            break;
        delay(10);
    }
    if (response != 0x00) {
        sd_force_idle();
        return -2;
    }

    if (sd_version == 2)
        sd_send_command(CMD58_READ_OCR, 0);

    spi_slow = 0;
    sd_force_idle();
    return 0;
}

int sd_init(void)
{
    int result = -1;
    for (int retries = 0; retries < 4; retries++) {
        result = _sd_init();
        if (result == 0)
            return 0;
        delay(20);
    }
    return result;
}

int sd_readsector(uint32_t start_block, uint8_t *buffer, uint32_t sector_count) {
    uint8_t response;
    uint32_t ctrl;
    int retries = 0;
    int i;
    if (sector_count == 0) {
        return 0;
    }
    CS_L();
    while (sector_count--) {
        // Request block read
        response = sd_send_command(CMD17_READ_SINGLE_BLOCK, start_block++);
        if(response != 0x00) {
            (void)response;
            sd_force_idle();
            return 0;
        }

        // Wait for start of block indicator
        while(spi_receive() != CMD_START_OF_BLOCK) {
            // Timeout
            if(retries > 5000) {
                sd_force_idle();
                return 0;
            }
	    ++retries;
        }

        // Perform block read (512 bytes)
        spi_readblock(buffer, 512);

        buffer += 512;

        // Ignore 16-bit CRC
        spi_receive();
        spi_receive();

        // Additional 8 SPI clocks
        spi_sendrecv(0xFF);
    }
    sd_force_idle();
    return 1;
}

int sd_writesector(uint32_t start_block, uint8_t *buffer, uint32_t sector_count)
{
  (void)start_block;
  (void)buffer;
  (void)sector_count;
  return 0;
}


