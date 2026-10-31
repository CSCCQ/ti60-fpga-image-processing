/* Gray autonomous boot. SPI driver/register contract comes from the generated
 * Efinix BSP. Flash access here is READ ONLY; programming is a host operation.
 * 0x000000..0x3fffff: FPGA image; 0x400000: checked header + application. */
#include <stdint.h>
#include "soc.h"
#include "clint.h"
static void bsp_uDelay(uint32_t us) {
    /* This generated CPU has no cycle CSR read mapping. Use its CLINT,
     * as the official BSP does, at the actual 96 MHz peripheral clock. */
    clint_uDelay(us, 96000000u, SYSTEM_CLINT_CTRL);
}
#include "spi.h"

#define FLASH_APP 0x00400000u
#define FLASH_END 0x00800000u
#define APP_BASE  0x00001000u
#define APP_END   0x01000000u
#define SPI      SYSTEM_SPI_0_IO_CTRL
#define STATUS   ((volatile uint32_t *)0xf9000fe0u)
#define DDR_READY (*(volatile uint32_t *)IO_APB_SLAVE_0_INPUT)

static void stop(uint32_t error) __attribute__((noreturn));
static void stop(uint32_t error) {
    STATUS[2] = error;
    for (;;) __asm__ volatile ("nop");
}
static uint32_t crc32(const volatile uint8_t *p, uint32_t n) {
    uint32_t crc = ~0u;
    while (n--) {
        crc ^= *p++;
        for (unsigned bit = 0; bit < 8; ++bit)
            crc = (crc >> 1) ^ (0xedb88320u & (0u - (crc & 1u)));
    }
    return ~crc;
}
static void read_begin(uint32_t address) {
    spi_select(SPI, 0);
    spi_write(SPI, 0x03);
    spi_write(SPI, address >> 16);
    spi_write(SPI, address >> 8);
    spi_write(SPI, address);
}

void boot_main(void) {
    for (unsigned i = 0; i < 8; ++i) STATUS[i] = 0;
    STATUS[0] = 0x42595247u;
    STATUS[1] = 1; /* Wait for DDR calibration before touching application RAM. */
    uint32_t limit = 100000000u;
    while ((DDR_READY & 3u) != 3u) if (!--limit) stop(1);

    STATUS[1] = 2;
    Spi_Config cfg = {0, 0, 0, 7, 16, 16, 32}; /* Mode 0, 6 MHz at 96 MHz */
    spi_applyConfig(SPI, &cfg);
    spi_waitXferBusy(SPI);
    spi_diselect(SPI, 0);
    spi_select(SPI, 0); spi_write(SPI, 0xab); spi_diselect(SPI, 0);
    for (volatile unsigned delay = 0; delay < 2000; ++delay) {}
    spi_select(SPI, 0); spi_write(SPI, 0x9f);
    uint32_t jedec = (uint32_t)spi_read(SPI) << 16;
    jedec |= (uint32_t)spi_read(SPI) << 8;
    jedec |= spi_read(SPI); spi_diselect(SPI, 0);
    STATUS[3] = jedec;
    if ((jedec >> 16) != 0xef || (jedec & 0xff) != 0x17) stop(2);

    STATUS[1] = 3;
    uint32_t header[16];
    read_begin(FLASH_APP);
    for (unsigned i = 0; i < sizeof(header); ++i)
        ((uint8_t *)header)[i] = spi_read(SPI);
    spi_diselect(SPI, 0);
    if (header[0] != 0x44595247u || header[1] != 1 || header[2] != 64 ||
        crc32((const uint8_t *)header, 28) != header[7]) stop(3);
    uint32_t length = header[3], entry = header[5];
    if (!length || length > FLASH_END-FLASH_APP-64 || length > APP_END-APP_BASE ||
        header[4] != APP_BASE || (entry & 3) || entry < APP_BASE ||
        entry >= APP_BASE+length) stop(4);
    STATUS[4] = length; STATUS[5] = header[6];

    STATUS[1] = 4;
    read_begin(FLASH_APP + 64);
    volatile uint8_t *dst = (volatile uint8_t *)APP_BASE;
    for (uint32_t i = 0; i < length; ++i) dst[i] = spi_read(SPI);
    spi_diselect(SPI, 0);
    /* VexRiscv data-cache flush/writeback from vendor vexriscv.h. Ensure
     * instructions and TinyML DMA see DDR data, not dirty CPU cache lines. */
    __asm__ volatile ("fence rw,rw\n.word 0x500f\nfence rw,rw" ::: "memory");
    STATUS[1] = 5;
    uint32_t actual = crc32(dst, length);
    STATUS[6] = actual;
    if (actual != header[6]) stop(5);
    STATUS[1] = 6; /* CRC verified; jump to the original unmodified ELF entry. */
    __asm__ volatile ("fence.i\nmv t0,%0\nli a0,0\nli a1,0\njr t0"
                      :: "r"(entry) : "t0", "a0", "a1", "memory");
    __builtin_unreachable();
}
