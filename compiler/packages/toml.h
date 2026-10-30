#pragma once

#include "diagnostics/diagnostics.h"
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

// The TOML subset used by Mettle.toml and Mettle.lock: tables, arrays of
// tables, dotted keys, basic/literal strings, integers, booleans, arrays and
// inline tables. Floats, dates and multi-line strings are rejected.
namespace mettle::packages::toml {
struct Value {
  enum class Kind { String, Integer, Boolean, Array, Table };
  Kind kind = Kind::Table;
  // The value itself, and the key that introduced it (empty for the root).
  Span span, key;
  std::string string;
  std::int64_t integer = 0;
  bool boolean = false;
  std::vector<Value> array;
  std::vector<std::pair<std::string, Value>> table;

  const Value *find(std::string_view name) const;
};

// Reports syntax faults as `phase` diagnostics; returns the root table.
std::optional<Value> parse(const Source &source, Diagnostics &diagnostics,
                           const std::string &phase);
// A quoted TOML basic string with the escapes this parser accepts.
std::string quote(std::string_view text);
} // namespace mettle::packages::toml
