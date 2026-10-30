#pragma once

#include <cstddef>
#include <string>
#include <string_view>

namespace mettle {
inline std::string displayPath(std::string_view canonical) {
  std::string result;
  result.reserve(canonical.size());
  for (std::size_t i = 0; i < canonical.size(); ++i) {
    if (canonical[i] == ':' && i + 1 < canonical.size() &&
        canonical[i + 1] == ':') {
      result += '.';
      ++i;
    } else
      result += canonical[i];
  }
  return result;
}
} // namespace mettle
