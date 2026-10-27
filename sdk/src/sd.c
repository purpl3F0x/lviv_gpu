#include "sd.h"

#include <malloc.h> // memalign
#include <stdlib.h>
#include <string.h>

#include "ff.h"

// FatFs as the BSP's xilffs is built (vitis_workspace.py's BSP_LIBS): with long file names. Headers
// that say otherwise lay its structures out smaller than the library fills them (FILINFO's name).
#if !FF_USE_LFN
#error "ff.h without long file names (FF_USE_LFN), unlike the BSP's xilffs: make vitis"
#endif

// The A53's cache line: the card's DMA writes whole ones, which the driver invalidates
#define CACHE_LINE 64

_Static_assert(SD_NO_FILE == FR_NO_FILE, "sd.h's SD_NO_FILE is FatFs's FR_NO_FILE");

static FATFS fs;
static int mounted;

static FRESULT mount(void)
{
    if (mounted)
        return FR_OK;
    const FRESULT r = f_mount(&fs, "0:/", 1); // now, so that no card is an error here
    mounted = r == FR_OK;
    return r;
}

// After an error of the card itself, mounted again at the next call
static int forget_card(FRESULT r)
{
    if (r == FR_NOT_READY || r == FR_DISK_ERR)
        mounted = 0;
    return r;
}

int sd_scan(const char *path, void (*found)(const sd_entry_t *entry, void *user), void *user)
{
    FRESULT r = mount();
    if (r != FR_OK)
        return r;
    DIR dir;
    r = f_opendir(&dir, path);
    if (r != FR_OK)
        return forget_card(r);
    for (;;)
    {
        FILINFO info;
        r = f_readdir(&dir, &info);
        if (r != FR_OK || info.fname[0] == '\0') // an error, or the end
            break;
        const sd_entry_t entry = {info.fname, (info.fattrib & AM_DIR) != 0, (uint64_t)info.fsize};
        found(&entry, user);
    }
    f_closedir(&dir);
    return forget_card(r);
}

int sd_read(const char *path, void **data, size_t *size, size_t padding)
{
    *data = NULL;
    *size = 0;
    FRESULT r = mount();
    if (r != FR_OK)
        return r;
    FIL file;
    r = f_open(&file, path, FA_READ);
    if (r != FR_OK)
        return forget_card(r);
    const size_t n = (size_t)f_size(&file);
    uint8_t *buffer = memalign(CACHE_LINE, (n + padding + CACHE_LINE - 1) / CACHE_LINE * CACHE_LINE);
    if (!buffer)
    {
        f_close(&file);
        return FR_NOT_ENOUGH_CORE;
    }
    UINT got = 0;
    r = f_read(&file, buffer, (UINT)n, &got);
    f_close(&file);
    if (r == FR_OK && got != n)
        r = FR_INT_ERR; // the file shorter than its size
    if (r != FR_OK)
    {
        free(buffer);
        return forget_card(r);
    }
    memset(buffer + n, 0, padding);
    *data = buffer;
    *size = n;
    return 0;
}

const char *sd_error_name(int error)
{
    static const char *const names[] = {
        "FR_OK",
        "FR_DISK_ERR",
        "FR_INT_ERR",
        "FR_NOT_READY",
        "FR_NO_FILE",
        "FR_NO_PATH",
        "FR_INVALID_NAME",
        "FR_DENIED",
        "FR_EXIST",
        "FR_INVALID_OBJECT",
        "FR_WRITE_PROTECTED",
        "FR_INVALID_DRIVE",
        "FR_NOT_ENABLED",
        "FR_NO_FILESYSTEM",
        "FR_MKFS_ABORTED",
        "FR_TIMEOUT",
        "FR_LOCKED",
        "FR_NOT_ENOUGH_CORE",
        "FR_TOO_MANY_OPEN_FILES",
        "FR_INVALID_PARAMETER",
    };
    return error >= 0 && error < (int)(sizeof names / sizeof names[0]) ? names[error] : "FR_?";
}
