#pragma once

#include "metadata/type_graph.h"
#include "source/source.h"
#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <string_view>

namespace mettle::metadata {
struct SourceReference {
  std::string revision;
  std::uint32_t begin = 0, end = 0;
};
struct EncodeReferences {
  std::function<std::optional<std::uint32_t>(Type)> type;
  std::function<std::optional<SourceReference>(Span)> source;
  std::function<std::optional<std::string>(SymbolKind, std::uint32_t)> symbol;
};
struct DecodeReferences {
  std::function<std::optional<Type>(std::uint32_t)> type;
  std::function<std::optional<Span>(const SourceReference &)> source;
  std::function<std::optional<std::uint32_t>(SymbolKind, std::string_view)>
      symbol;
};
} // namespace mettle::metadata
