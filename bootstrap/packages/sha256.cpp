#include "packages/sha256.h"
#include <algorithm>
#if defined(__x86_64__)
#include <immintrin.h>
#endif

namespace mettle::packages {
namespace {
constexpr std::array<std::uint32_t, 64> k{
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

std::uint32_t rotate(std::uint32_t value, unsigned bits) {
  return (value >> bits) | (value << (32 - bits));
}

void softwareBlocks(std::array<std::uint32_t, 8> &state,
                    const unsigned char *bytes, std::size_t count) {
  for (; count; --count, bytes += 64) {
    std::uint32_t w[64];
    for (std::size_t i = 0; i < 16; ++i)
      w[i] = (std::uint32_t{bytes[i * 4]} << 24) |
             (std::uint32_t{bytes[i * 4 + 1]} << 16) |
             (std::uint32_t{bytes[i * 4 + 2]} << 8) | bytes[i * 4 + 3];
    for (std::size_t i = 16; i < 64; ++i) {
      auto s0 = rotate(w[i - 15], 7) ^ rotate(w[i - 15], 18) ^ (w[i - 15] >> 3);
      auto s1 = rotate(w[i - 2], 17) ^ rotate(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    auto [a, b, c, d, e, f, g, h] = state;
    for (std::size_t i = 0; i < 64; ++i) {
      auto s1 = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25);
      auto choose = (e & f) ^ (~e & g);
      auto t1 = h + s1 + choose + k[i] + w[i];
      auto s0 = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22);
      auto majority = (a & b) ^ (a & c) ^ (b & c);
      auto t2 = s0 + majority;
      h = g;
      g = f;
      f = e;
      e = d + t1;
      d = c;
      c = b;
      b = a;
      a = t1 + t2;
    }
    state[0] += a;
    state[1] += b;
    state[2] += c;
    state[3] += d;
    state[4] += e;
    state[5] += f;
    state[6] += g;
    state[7] += h;
  }
}

#if defined(__x86_64__)
// The SHA extensions hash several times faster than the portable rounds, and
// the build cache re-hashes every library blob it reads.
__attribute__((target("sha,sse4.1,ssse3"))) void
hardwareBlocks(std::array<std::uint32_t, 8> &state, const unsigned char *bytes,
               std::size_t count) {
  const __m128i swap =
      _mm_set_epi64x(0x0c0d0e0f08090a0bLL, 0x0405060700010203LL);
  __m128i swapped =
      _mm_shuffle_epi32(_mm_loadu_si128((const __m128i *)&state[0]), 0xB1);
  __m128i efgh =
      _mm_shuffle_epi32(_mm_loadu_si128((const __m128i *)&state[4]), 0x1B);
  __m128i abef = _mm_alignr_epi8(swapped, efgh, 8);
  __m128i cdgh = _mm_blend_epi16(efgh, swapped, 0xF0);
  for (; count; --count, bytes += 64) {
    const __m128i savedAbef = abef, savedCdgh = cdgh;
    __m128i w[4];
    for (int i = 0; i < 4; ++i)
      w[i] = _mm_shuffle_epi8(
          _mm_loadu_si128((const __m128i *)(bytes + 16 * i)), swap);
    for (int r = 0; r < 16; ++r) {
      __m128i message = _mm_add_epi32(
          w[r & 3], _mm_loadu_si128((const __m128i *)&k[4 * r]));
      cdgh = _mm_sha256rnds2_epu32(cdgh, abef, message);
      message = _mm_shuffle_epi32(message, 0x0E);
      abef = _mm_sha256rnds2_epu32(abef, cdgh, message);
      if (r < 12) {
        __m128i next = _mm_sha256msg1_epu32(w[r & 3], w[(r + 1) & 3]);
        next = _mm_add_epi32(
            next, _mm_alignr_epi8(w[(r + 3) & 3], w[(r + 2) & 3], 4));
        w[r & 3] = _mm_sha256msg2_epu32(next, w[(r + 3) & 3]);
      }
    }
    abef = _mm_add_epi32(abef, savedAbef);
    cdgh = _mm_add_epi32(cdgh, savedCdgh);
  }
  __m128i feba = _mm_shuffle_epi32(abef, 0x1B);
  __m128i dchg = _mm_shuffle_epi32(cdgh, 0xB1);
  _mm_storeu_si128((__m128i *)&state[0], _mm_blend_epi16(feba, dchg, 0xF0));
  _mm_storeu_si128((__m128i *)&state[4], _mm_alignr_epi8(dchg, feba, 8));
}
#endif

void blocks(std::array<std::uint32_t, 8> &state, const unsigned char *bytes,
            std::size_t count) {
#if defined(__x86_64__)
  static const bool hardware = __builtin_cpu_supports("sha") &&
                               __builtin_cpu_supports("sse4.1");
  if (hardware)
    return hardwareBlocks(state, bytes, count);
#endif
  softwareBlocks(state, bytes, count);
}
} // namespace

Sha256::Sha256()
    : state{0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19} {}

void Sha256::block(const unsigned char *bytes) { blocks(state, bytes, 1); }

void Sha256::update(std::string_view data) {
  total += data.size();
  auto *bytes = reinterpret_cast<const unsigned char *>(data.data());
  std::size_t size = data.size();
  if (buffered) {
    auto take = std::min(size, buffer.size() - buffered);
    std::copy_n(bytes, take, buffer.begin() + static_cast<long>(buffered));
    buffered += take;
    bytes += take;
    size -= take;
    if (buffered == buffer.size()) {
      blocks(state, buffer.data(), 1);
      buffered = 0;
    }
  }
  if (const auto whole = size / buffer.size()) {
    blocks(state, bytes, whole);
    bytes += whole * buffer.size();
    size -= whole * buffer.size();
  }
  if (size) {
    std::copy_n(bytes, size, buffer.begin());
    buffered = size;
  }
}

std::string Sha256::finish() {
  auto bits = total * 8;
  unsigned char pad = 0x80;
  update(std::string_view(reinterpret_cast<const char *>(&pad), 1));
  unsigned char zero = 0;
  while (buffered != 56)
    update(std::string_view(reinterpret_cast<const char *>(&zero), 1));
  std::array<unsigned char, 8> length{};
  for (std::size_t i = 0; i < 8; ++i)
    length[i] = static_cast<unsigned char>(bits >> (56 - 8 * i));
  update(std::string_view(reinterpret_cast<const char *>(length.data()), 8));
  static constexpr char hex[] = "0123456789abcdef";
  std::string digest;
  for (auto word : state)
    for (int shift = 28; shift >= 0; shift -= 4)
      digest += hex[(word >> shift) & 0xf];
  return digest;
}
} // namespace mettle::packages
