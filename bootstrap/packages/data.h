#pragma once

#include "diagnostics/diagnostics.h"
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace mettle::packages::data {
struct Value {
  enum class Kind { String, Integer, Number, Boolean, None, Array, Object };
  Kind kind = Kind::Object;
  // The value itself, and the key that introduced it (empty for the root).
  Span span, key;
  std::string string;
  std::int64_t integer = 0;
  bool boolean = false;
  std::vector<Value> array;
  std::vector<std::pair<std::string, Value>> object;

  // Declared here and defaulted after the class: libstdc++ requires the
  // recursive element types to be complete where the members are defined.
  Value();
  Value(const Value &);
  Value(Value &&) noexcept;
  Value &operator=(const Value &);
  Value &operator=(Value &&) noexcept;
  ~Value();

  const Value *find(std::string_view name) const;
};

inline Value::Value() = default;
inline Value::Value(const Value &) = default;
inline Value::Value(Value &&) noexcept = default;
inline Value &Value::operator=(const Value &) = default;
inline Value &Value::operator=(Value &&) noexcept = default;
inline Value::~Value() = default;

// Reports syntax faults as `phase` diagnostics; preserves source byte spans.
std::optional<Value> parse(const Source &source, Diagnostics &diagnostics,
                           const std::string &phase);
// A quoted .mettle string, using Mettle's ordinary text escapes.
std::string quote(std::string_view text);
} // namespace mettle::packages::data
