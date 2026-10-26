# Known issues

## The frontend draws a triangle a tile off when its box misses the tile

A triangle sent to a tile left of or above its bounding box (as the frontend computes it, in fixed
point) is drawn again a tile (128 px) to the left or up: the box clamped to the tile is empty, and
its width in the tile (`bb_width`) wraps. Binning with float positions does that to a triangle
starting within 1/2048 of a pixel below a tile boundary, which `fp_to_fx14_10` rounds up to the
boundary (Suzanne at 180° in `gl_test`).

**Workaround:** lviv_gl bins with the frontend's box (`frontend_min`, `frontend_max` in
`sdk/lviv_gl/lviv_geom.cpp`). `dv/raster_sw` still bins with floor and ceil; its scene is not
affected.

**Fix (for now):** in `raster_frontend()` (`scripts/frontend/generator_fixed_point.py`), clamp the
box's minimum to at most the tile's last quad and its maximum to at least its first, so that an
empty box draws nothing. Alternative fix: Patch Frontend to reject empty BBs
