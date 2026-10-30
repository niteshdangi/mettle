#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <string_view>

namespace mettle::packages {
// Incremental SHA-256 (FIPS 180-4) for lockfile content checksums.
class Sha256 {
public:
  Sha256();
  void update(std::string_view data);
  // Lowercase hexadecimal digest; the hasher is finished afterwards.
  std::string finish();

private:
  void block(const unsigned char *bytes);
  std::array<std::uint32_t, 8> state;
  std::array<unsigned char, 64> buffer{};
  std::uint64_t total = 0;
  std::size_t buffered = 0;
};
} // namespace mettle::packages
