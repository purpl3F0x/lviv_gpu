// The SD card in the ZCU104's slot (the PS's SD1), through the BSP's xilffs (FatFs, with long file
// names: vitis_workspace.py's BSP_LIBS), standalone BSP. Its FAT volume is FatFs's logical drive 0,
// paths "0:/...", mounted by the first call that needs it (again after the card failed, so that
// another can be put in).
#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

// An entry of a directory, for sd_scan: its name, whether it is a directory, its size in bytes
typedef struct
{
    const char *name;
    int directory;
    uint64_t size;
} sd_entry_t;

// Calls found(entry, user) for each file and directory in path, in the directory's order (the entry
// lasts until found returns). Returns 0, or FatFs's error (FRESULT, ff.h): no card, no FAT volume
// on it, no such directory, ...
int sd_scan(const char *path, void (*found)(const sd_entry_t *entry, void *user), void *user);

// The file at path read whole into *data, *size bytes, with padding zero bytes after it: memory
// from the heap (free() it), aligned to cache lines, whole ones, as the card's DMA writes it.
// Returns 0, or FatFs's error (FR_NOT_ENOUGH_CORE: no memory for it); *data NULL then.
int sd_read(const char *path, void **data, size_t *size, size_t padding);

// sd_read's error for a file that is not there (FatFs's FR_NO_FILE)
#define SD_NO_FILE 4

// FatFs's name of an error sd_scan or sd_read returned: "FR_NOT_READY", ...
const char *sd_error_name(int error);

#ifdef __cplusplus
}
#endif
