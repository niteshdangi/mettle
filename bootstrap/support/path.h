#pragma once

#include <cstddef>
#include <span>
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

inline std::string
displayPath(std::string_view canonical,
            std::span<const std::string_view> namesInMessage) {
  const auto separator = canonical.rfind("::");
  if (separator == std::string_view::npos)
    return std::string(canonical);
  const auto shortName = canonical.substr(separator + 2);
  for (auto name : namesInMessage) {
    if (name == canonical)
      continue;
    const auto otherSeparator = name.rfind("::");
    const auto otherShort = otherSeparator == std::string_view::npos
                                ? name
                                : name.substr(otherSeparator + 2);
    if (otherShort == shortName)
      return displayPath(canonical);
  }
  return std::string(shortName);
}
} // namespace mettle
