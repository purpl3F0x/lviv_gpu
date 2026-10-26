/* gl_test's frame memory for lviv_gl (main.cpp gives it to lviv_gl_init): where the GPU reads each
 * frame's triangles and their tile masks from, 256 MiB at a fixed address in the PS's DDR4, above
 * the program (the PL's DDR4 later). At 104 bytes a triangle, about 2.58 million triangles a
 * frame. NOLOAD: none of it in the ELF, nothing downloaded, nothing cleared at start-up.
 *
 * Added to the application's own linker script (Vitis's lscript.ld) as a second -T
 * (VITIS_APP_LDFLAGS_gl_test, bd/gpu_test/Makefile). The link fails if a section of the program
 * overlaps it. The build does not track this file: after a change, rebuild gl_test clean. */
LVIV_FRAME_BASE = 0x60000000;
LVIV_FRAME_SIZE = 0x10000000;

SECTIONS
{
    .lviv_frame LVIV_FRAME_BASE (NOLOAD) :
    {
        lviv_frame_start = .;
        . += LVIV_FRAME_SIZE;
        lviv_frame_end = .;
    }
}
