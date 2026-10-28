// SIMD for sw_raster.c: float and int32 lanes, a mask's lanes all ones or zeros. SW_RASTER_SIMD
// picks it, by default from what the compiler targets:
//   SW_SIMD_AVX2    x86-64 with AVX2 and FMA (-mavx2 -mfma): 8 lanes, a block of 4 x 2 pixels
//   SW_SIMD_NEON    AArch64's Advanced SIMD (the A53's): 4 lanes, 2 x 2 pixels
//   SW_SIMD_VECTOR  GCC's vector extensions, any target: 4 lanes as NEON's, plain C per lane where
//                   C has no operator
//   SW_SIMD_NONE    no SIMD (SW_LANES 0): sw_raster.c's scalar code
#pragma once

#include <stdint.h>

#define SW_SIMD_NONE 0
#define SW_SIMD_VECTOR 1
#define SW_SIMD_NEON 2
#define SW_SIMD_AVX2 3

#ifndef SW_RASTER_SIMD
#if defined(__AVX2__) && defined(__FMA__)
#define SW_RASTER_SIMD SW_SIMD_AVX2
#elif defined(__aarch64__) && defined(__ARM_NEON)
#define SW_RASTER_SIMD SW_SIMD_NEON
#elif defined(__GNUC__)
#define SW_RASTER_SIMD SW_SIMD_VECTOR
#else
#define SW_RASTER_SIMD SW_SIMD_NONE
#endif
#endif

#ifdef __GNUC__
#define SW_INLINE static inline __attribute__((always_inline))
#else
#define SW_INLINE static inline
#endif

#if SW_RASTER_SIMD == SW_SIMD_AVX2

#include <immintrin.h>

#define SW_LANES 8
#define SW_ALIGN 32
#define SW_SIMD "AVX2"
typedef __m256 vf;
typedef __m256i vi;

SW_INLINE vf vf_set1(float a)
{
    return _mm256_set1_ps(a);
}
SW_INLINE vf vf_load(const float *p)
{
    return _mm256_load_ps(p);
}
SW_INLINE void vf_store(float *p, vf a)
{
    _mm256_store_ps(p, a);
}
SW_INLINE vf vf_add(vf a, vf b)
{
    return _mm256_add_ps(a, b);
}
SW_INLINE vf vf_sub(vf a, vf b)
{
    return _mm256_sub_ps(a, b);
}
SW_INLINE vf vf_mul(vf a, vf b)
{
    return _mm256_mul_ps(a, b);
}
SW_INLINE vf vf_madd(vf a, vf b, vf c) // a * b + c
{
    return _mm256_fmadd_ps(a, b, c);
}
SW_INLINE vf vf_min(vf a, vf b) // b where a is NaN
{
    return _mm256_min_ps(a, b);
}
SW_INLINE vf vf_max(vf a, vf b)
{
    return _mm256_max_ps(a, b);
}
// 1 / a to about 23 bits: the estimate and a Newton step
SW_INLINE vf vf_rcp(vf a)
{
    const vf r = _mm256_rcp_ps(a);
    return _mm256_mul_ps(r, _mm256_fnmadd_ps(a, r, _mm256_set1_ps(2.0f)));
}
SW_INLINE vf vf_floor(vf a)
{
    return _mm256_floor_ps(a);
}
SW_INLINE vi vf_lt(vf a, vf b)
{
    return _mm256_castps_si256(_mm256_cmp_ps(a, b, _CMP_LT_OQ));
}
SW_INLINE vi vf_le(vf a, vf b)
{
    return _mm256_castps_si256(_mm256_cmp_ps(a, b, _CMP_LE_OQ));
}
SW_INLINE vi vf_eq(vf a, vf b)
{
    return _mm256_castps_si256(_mm256_cmp_ps(a, b, _CMP_EQ_OQ));
}
SW_INLINE vi vf_gt(vf a, vf b)
{
    return _mm256_castps_si256(_mm256_cmp_ps(a, b, _CMP_GT_OQ));
}
SW_INLINE vf vf_select(vi m, vf a, vf b) // m ? a : b
{
    return _mm256_blendv_ps(b, a, _mm256_castsi256_ps(m));
}
SW_INLINE vi vf_round(vf a) // to the nearest, ties to even
{
    return _mm256_cvtps_epi32(a);
}
SW_INLINE vi vf_trunc(vf a)
{
    return _mm256_cvttps_epi32(a);
}
SW_INLINE vf vi_float(vi a)
{
    return _mm256_cvtepi32_ps(a);
}

SW_INLINE vi vi_set1(int32_t a)
{
    return _mm256_set1_epi32(a);
}
SW_INLINE vi vi_load(const void *p)
{
    return _mm256_load_si256((const __m256i *)p);
}
SW_INLINE void vi_store(void *p, vi a)
{
    _mm256_store_si256((__m256i *)p, a);
}
SW_INLINE vi vi_add(vi a, vi b)
{
    return _mm256_add_epi32(a, b);
}
SW_INLINE vi vi_sub(vi a, vi b)
{
    return _mm256_sub_epi32(a, b);
}
SW_INLINE vi vi_mul(vi a, vi b) // the low 32 bits
{
    return _mm256_mullo_epi32(a, b);
}
SW_INLINE vi vi_and(vi a, vi b)
{
    return _mm256_and_si256(a, b);
}
SW_INLINE vi vi_or(vi a, vi b)
{
    return _mm256_or_si256(a, b);
}
SW_INLINE vi vi_gt(vi a, vi b)
{
    return _mm256_cmpgt_epi32(a, b);
}
SW_INLINE vi vi_eq(vi a, vi b)
{
    return _mm256_cmpeq_epi32(a, b);
}
SW_INLINE vi vi_min(vi a, vi b)
{
    return _mm256_min_epi32(a, b);
}
SW_INLINE vi vi_max(vi a, vi b)
{
    return _mm256_max_epi32(a, b);
}
SW_INLINE vi vi_select(vi m, vi a, vi b)
{
    return _mm256_blendv_epi8(b, a, m);
}
#define vi_sll(a, n) _mm256_slli_epi32(a, n)
#define vi_srl(a, n) _mm256_srli_epi32(a, n)
#define vi_sra(a, n) _mm256_srai_epi32(a, n)
SW_INLINE int vi_any(vi m)
{
    return !_mm256_testz_si256(m, m);
}
SW_INLINE unsigned vi_bits(vi m) // bit j for lane j
{
    return (unsigned)_mm256_movemask_ps(_mm256_castsi256_ps(m));
}
SW_INLINE vi vi_gather(const uint32_t *base, vi index)
{
    return _mm256_i32gather_epi32((const int *)base, index, 4);
}
// Each lane's pixel in its block: its column, its row
SW_INLINE vi vi_column(void)
{
    return _mm256_setr_epi32(0, 1, 2, 3, 0, 1, 2, 3);
}
SW_INLINE vi vi_row(void)
{
    return _mm256_setr_epi32(0, 0, 0, 0, 1, 1, 1, 1);
}
// B, G, R and A, each rounded to its byte (saturated), to ARGB words
SW_INLINE vi vi_argb(vf b, vf g, vf r, vf a)
{
    const __m256i bg = _mm256_packus_epi32(_mm256_cvtps_epi32(b), _mm256_cvtps_epi32(g));
    const __m256i ra = _mm256_packus_epi32(_mm256_cvtps_epi32(r), _mm256_cvtps_epi32(a));
    // Each 128 bits B0-3 G0-3 R0-3 A0-3, then a pixel's 4 bytes together
    const __m256i order = _mm256_setr_epi8(0, 4, 8, 12, 1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15, 0, 4, 8, 12, 1, 5, 9,
                                           13, 2, 6, 10, 14, 3, 7, 11, 15);
    return _mm256_shuffle_epi8(_mm256_packus_epi16(bg, ra), order);
}
// GL_MODULATE: each byte times the other's, of 255 as 1, rounded
SW_INLINE vi vi_modulate(vi c, vi t)
{
    const __m256i zero = _mm256_setzero_si256(), bias = _mm256_set1_epi16(128), m = _mm256_set1_epi16(257);
    const __m256i lo = _mm256_mullo_epi16(_mm256_unpacklo_epi8(c, zero), _mm256_unpacklo_epi8(t, zero));
    const __m256i hi = _mm256_mullo_epi16(_mm256_unpackhi_epi8(c, zero), _mm256_unpackhi_epi8(t, zero));
    // x / 255 = (x + 128) * 257 >> 16
    return _mm256_packus_epi16(_mm256_mulhi_epu16(_mm256_add_epi16(lo, bias), m),
                               _mm256_mulhi_epu16(_mm256_add_epi16(hi, bias), m));
}
// A block's rows, at row0 and row1
SW_INLINE void vi_store_rows(uint32_t *row0, uint32_t *row1, vi a)
{
    _mm_storeu_si128((__m128i *)row0, _mm256_castsi256_si128(a));
    _mm_storeu_si128((__m128i *)row1, _mm256_extracti128_si256(a, 1));
}

#elif SW_RASTER_SIMD == SW_SIMD_NEON

#include <arm_neon.h>

#define SW_LANES 4
#define SW_ALIGN 16
#define SW_SIMD "NEON"
typedef float32x4_t vf;
typedef int32x4_t vi;

SW_INLINE vf vf_set1(float a)
{
    return vdupq_n_f32(a);
}
SW_INLINE vf vf_load(const float *p)
{
    return vld1q_f32(p);
}
SW_INLINE void vf_store(float *p, vf a)
{
    vst1q_f32(p, a);
}
SW_INLINE vf vf_add(vf a, vf b)
{
    return vaddq_f32(a, b);
}
SW_INLINE vf vf_sub(vf a, vf b)
{
    return vsubq_f32(a, b);
}
SW_INLINE vf vf_mul(vf a, vf b)
{
    return vmulq_f32(a, b);
}
SW_INLINE vf vf_madd(vf a, vf b, vf c) // a * b + c
{
    return vfmaq_f32(c, a, b);
}
SW_INLINE vf vf_min(vf a, vf b) // b where a is NaN
{
    return vbslq_f32(vcltq_f32(a, b), a, b);
}
SW_INLINE vf vf_max(vf a, vf b)
{
    return vbslq_f32(vcgtq_f32(a, b), a, b);
}
// 1 / a to about 23 bits: the estimate and two Newton steps
SW_INLINE vf vf_rcp(vf a)
{
    vf r = vrecpeq_f32(a);
    r = vmulq_f32(r, vrecpsq_f32(a, r));
    return vmulq_f32(r, vrecpsq_f32(a, r));
}
SW_INLINE vf vf_floor(vf a)
{
    return vrndmq_f32(a);
}
SW_INLINE vi vf_lt(vf a, vf b)
{
    return vreinterpretq_s32_u32(vcltq_f32(a, b));
}
SW_INLINE vi vf_le(vf a, vf b)
{
    return vreinterpretq_s32_u32(vcleq_f32(a, b));
}
SW_INLINE vi vf_eq(vf a, vf b)
{
    return vreinterpretq_s32_u32(vceqq_f32(a, b));
}
SW_INLINE vi vf_gt(vf a, vf b)
{
    return vreinterpretq_s32_u32(vcgtq_f32(a, b));
}
SW_INLINE vf vf_select(vi m, vf a, vf b) // m ? a : b
{
    return vbslq_f32(vreinterpretq_u32_s32(m), a, b);
}
SW_INLINE vi vf_round(vf a) // to the nearest, ties to even
{
    return vcvtnq_s32_f32(a);
}
SW_INLINE vi vf_trunc(vf a)
{
    return vcvtq_s32_f32(a);
}
SW_INLINE vf vi_float(vi a)
{
    return vcvtq_f32_s32(a);
}

SW_INLINE vi vi_set1(int32_t a)
{
    return vdupq_n_s32(a);
}
SW_INLINE vi vi_load(const void *p)
{
    return vld1q_s32((const int32_t *)p);
}
SW_INLINE void vi_store(void *p, vi a)
{
    vst1q_s32((int32_t *)p, a);
}
SW_INLINE vi vi_add(vi a, vi b)
{
    return vaddq_s32(a, b);
}
SW_INLINE vi vi_sub(vi a, vi b)
{
    return vsubq_s32(a, b);
}
SW_INLINE vi vi_mul(vi a, vi b) // the low 32 bits
{
    return vmulq_s32(a, b);
}
SW_INLINE vi vi_and(vi a, vi b)
{
    return vandq_s32(a, b);
}
SW_INLINE vi vi_or(vi a, vi b)
{
    return vorrq_s32(a, b);
}
SW_INLINE vi vi_gt(vi a, vi b)
{
    return vreinterpretq_s32_u32(vcgtq_s32(a, b));
}
SW_INLINE vi vi_eq(vi a, vi b)
{
    return vreinterpretq_s32_u32(vceqq_s32(a, b));
}
SW_INLINE vi vi_min(vi a, vi b)
{
    return vminq_s32(a, b);
}
SW_INLINE vi vi_max(vi a, vi b)
{
    return vmaxq_s32(a, b);
}
SW_INLINE vi vi_select(vi m, vi a, vi b)
{
    return vbslq_s32(vreinterpretq_u32_s32(m), a, b);
}
#define vi_sll(a, n) vshlq_n_s32(a, n)
#define vi_srl(a, n) vreinterpretq_s32_u32(vshrq_n_u32(vreinterpretq_u32_s32(a), n))
#define vi_sra(a, n) vshrq_n_s32(a, n)
SW_INLINE int vi_any(vi m)
{
    return vmaxvq_u32(vreinterpretq_u32_s32(m)) != 0;
}
SW_INLINE unsigned vi_bits(vi m) // bit j for lane j
{
    const uint32x4_t bit = {1, 2, 4, 8};
    return vaddvq_u32(vandq_u32(vreinterpretq_u32_s32(m), bit));
}
SW_INLINE vi vi_gather(const uint32_t *base, vi index)
{
    uint32x4_t r = vdupq_n_u32(0);
    r = vsetq_lane_u32(base[vgetq_lane_s32(index, 0)], r, 0);
    r = vsetq_lane_u32(base[vgetq_lane_s32(index, 1)], r, 1);
    r = vsetq_lane_u32(base[vgetq_lane_s32(index, 2)], r, 2);
    r = vsetq_lane_u32(base[vgetq_lane_s32(index, 3)], r, 3);
    return vreinterpretq_s32_u32(r);
}
// Each lane's pixel in its block: its column, its row
SW_INLINE vi vi_column(void)
{
    const int32_t column[4] = {0, 1, 0, 1};
    return vld1q_s32(column);
}
SW_INLINE vi vi_row(void)
{
    const int32_t row[4] = {0, 0, 1, 1};
    return vld1q_s32(row);
}
// B, G, R and A, each rounded to its byte (saturated), to ARGB words
SW_INLINE vi vi_argb(vf b, vf g, vf r, vf a)
{
    const uint16x8_t bg = vcombine_u16(vqmovn_u32(vcvtnq_u32_f32(b)), vqmovn_u32(vcvtnq_u32_f32(g)));
    const uint16x8_t ra = vcombine_u16(vqmovn_u32(vcvtnq_u32_f32(r)), vqmovn_u32(vcvtnq_u32_f32(a)));
    // B0-3 G0-3 R0-3 A0-3, then a pixel's 4 bytes together
    const uint8x16_t order = {0, 4, 8, 12, 1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15};
    return vreinterpretq_s32_u8(vqtbl1q_u8(vcombine_u8(vqmovn_u16(bg), vqmovn_u16(ra)), order));
}
// GL_MODULATE: each byte times the other's, of 255 as 1, rounded
SW_INLINE vi vi_modulate(vi c, vi t)
{
    const uint8x16_t cb = vreinterpretq_u8_s32(c), tb = vreinterpretq_u8_s32(t);
    const uint16x8_t lo = vmull_u8(vget_low_u8(cb), vget_low_u8(tb)), hi = vmull_high_u8(cb, tb);
    // x / 255 = (x + ((x + 128) >> 8) + 128) >> 8
    return vreinterpretq_s32_u8(
        vcombine_u8(vrshrn_n_u16(vrsraq_n_u16(lo, lo, 8), 8), vrshrn_n_u16(vrsraq_n_u16(hi, hi, 8), 8)));
}
// A block's rows, at row0 and row1
SW_INLINE void vi_store_rows(uint32_t *row0, uint32_t *row1, vi a)
{
    const uint32x4_t u = vreinterpretq_u32_s32(a);
    vst1_u32(row0, vget_low_u32(u));
    vst1_u32(row1, vget_high_u32(u));
}

#elif SW_RASTER_SIMD == SW_SIMD_VECTOR

#include <string.h>

#define SW_LANES 4
#define SW_ALIGN 16
#define SW_SIMD "vector"
typedef float vf __attribute__((vector_size(16)));
typedef int32_t vi __attribute__((vector_size(16)));
typedef uint32_t vu __attribute__((vector_size(16)));

SW_INLINE vf vf_set1(float a)
{
    return (vf){a, a, a, a};
}
SW_INLINE vf vf_load(const float *p)
{
    vf a;
    memcpy(&a, p, sizeof a);
    return a;
}
SW_INLINE void vf_store(float *p, vf a)
{
    memcpy(p, &a, sizeof a);
}
SW_INLINE vf vf_add(vf a, vf b)
{
    return a + b;
}
SW_INLINE vf vf_sub(vf a, vf b)
{
    return a - b;
}
SW_INLINE vf vf_mul(vf a, vf b)
{
    return a * b;
}
SW_INLINE vf vf_madd(vf a, vf b, vf c) // a * b + c
{
    return a * b + c;
}
SW_INLINE vf vf_select(vi m, vf a, vf b) // m ? a : b
{
    vi r = (m & (vi)a) | (~m & (vi)b);
    return (vf)r;
}
SW_INLINE vf vf_min(vf a, vf b) // b where a is NaN
{
    return vf_select(a < b, a, b);
}
SW_INLINE vf vf_max(vf a, vf b)
{
    return vf_select(a > b, a, b);
}
SW_INLINE vf vf_rcp(vf a)
{
    return 1.0f / a;
}
SW_INLINE vf vf_floor(vf a) // for |a| < 2^31
{
    const vi i = __builtin_convertvector(a, vi);
    const vf f = __builtin_convertvector(i, vf);
    return f - (vf)((vi)(f > a) & (vi)vf_set1(1.0f));
}
SW_INLINE vi vf_lt(vf a, vf b)
{
    return a < b;
}
SW_INLINE vi vf_le(vf a, vf b)
{
    return a <= b;
}
SW_INLINE vi vf_eq(vf a, vf b)
{
    return a == b;
}
SW_INLINE vi vf_gt(vf a, vf b)
{
    return a > b;
}
SW_INLINE vi vf_trunc(vf a) // for |a| < 2^31
{
    return __builtin_convertvector(a, vi);
}
SW_INLINE vi vf_round(vf a) // to the nearest, ties away from 0, for |a| < 2^31
{
    return __builtin_convertvector(a + vf_select(a < vf_set1(0.0f), vf_set1(-0.5f), vf_set1(0.5f)), vi);
}
SW_INLINE vf vi_float(vi a)
{
    return __builtin_convertvector(a, vf);
}

SW_INLINE vi vi_set1(int32_t a)
{
    return (vi){a, a, a, a};
}
SW_INLINE vi vi_load(const void *p)
{
    vi a;
    memcpy(&a, p, sizeof a);
    return a;
}
SW_INLINE void vi_store(void *p, vi a)
{
    memcpy(p, &a, sizeof a);
}
SW_INLINE vi vi_add(vi a, vi b)
{
    return (vi)((vu)a + (vu)b);
}
SW_INLINE vi vi_sub(vi a, vi b)
{
    return (vi)((vu)a - (vu)b);
}
SW_INLINE vi vi_mul(vi a, vi b) // the low 32 bits
{
    return (vi)((vu)a * (vu)b);
}
SW_INLINE vi vi_and(vi a, vi b)
{
    return a & b;
}
SW_INLINE vi vi_or(vi a, vi b)
{
    return a | b;
}
SW_INLINE vi vi_gt(vi a, vi b)
{
    return a > b;
}
SW_INLINE vi vi_eq(vi a, vi b)
{
    return a == b;
}
SW_INLINE vi vi_select(vi m, vi a, vi b)
{
    return (m & a) | (~m & b);
}
SW_INLINE vi vi_min(vi a, vi b)
{
    return vi_select(a < b, a, b);
}
SW_INLINE vi vi_max(vi a, vi b)
{
    return vi_select(a > b, a, b);
}
#define vi_sll(a, n) ((vi)((vu)(a) << (n)))
#define vi_srl(a, n) ((vi)((vu)(a) >> (n)))
#define vi_sra(a, n) ((a) >> (n))
SW_INLINE unsigned vi_bits(vi m) // bit j for lane j
{
    return (unsigned)(m[0] & 1) | (unsigned)(m[1] & 1) << 1 | (unsigned)(m[2] & 1) << 2 | (unsigned)(m[3] & 1) << 3;
}
SW_INLINE int vi_any(vi m)
{
    return (m[0] | m[1] | m[2] | m[3]) != 0;
}
SW_INLINE vi vi_gather(const uint32_t *base, vi index)
{
    return (vi){(int32_t)base[index[0]], (int32_t)base[index[1]], (int32_t)base[index[2]], (int32_t)base[index[3]]};
}
// Each lane's pixel in its block: its column, its row
SW_INLINE vi vi_column(void)
{
    return (vi){0, 1, 0, 1};
}
SW_INLINE vi vi_row(void)
{
    return (vi){0, 0, 1, 1};
}
// B, G, R and A, each rounded to its byte (saturated), to ARGB words
SW_INLINE vi vi_argb(vf b, vf g, vf r, vf a)
{
    const vf lo = vf_set1(0.0f), hi = vf_set1(255.0f), half = vf_set1(0.5f);
    const vi ib = __builtin_convertvector(vf_max(vf_min(b + half, hi), lo), vi);
    const vi ig = __builtin_convertvector(vf_max(vf_min(g + half, hi), lo), vi);
    const vi ir = __builtin_convertvector(vf_max(vf_min(r + half, hi), lo), vi);
    const vi ia = __builtin_convertvector(vf_max(vf_min(a + half, hi), lo), vi);
    return ib | ig << 8 | ir << 16 | (vi)((vu)ia << 24);
}
// GL_MODULATE: each byte times the other's, of 255 as 1, rounded
SW_INLINE vi vi_modulate(vi c, vi t)
{
    vu out = {0, 0, 0, 0};
    for (int k = 0; k < 32; k += 8)
    {
        const vu x = ((vu)c >> k & 255u) * ((vu)t >> k & 255u) + 128u;
        out |= (x + (x >> 8)) >> 8 << k;
    }
    return (vi)out;
}
// A block's rows, at row0 and row1
SW_INLINE void vi_store_rows(uint32_t *row0, uint32_t *row1, vi a)
{
    row0[0] = (uint32_t)a[0];
    row0[1] = (uint32_t)a[1];
    row1[0] = (uint32_t)a[2];
    row1[1] = (uint32_t)a[3];
}

#else

#define SW_LANES 0
#define SW_SIMD "scalar"

#endif
