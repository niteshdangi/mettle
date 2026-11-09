#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace mettle::lsp {
// A JSON value (RFC 8259). Objects keep member order; lookup returns the first
// member of a name. Integers that fit 64 bits stay exact.
class Json {
public:
  enum class Type { Null, Boolean, Number, String, Array, Object };
  using Array = std::vector<Json>;
  using Object = std::vector<std::pair<std::string, Json>>;

  Json() = default;
  static Json boolean(bool value);
  static Json integer(std::int64_t value);
  static Json number(double value);
  static Json string(std::string value);
  static Json array(Array value = {});
  static Json object(Object value = {});

  Type type() const { return kind; }
  bool isNull() const { return kind == Type::Null; }
  std::optional<bool> asBoolean() const;
  std::optional<std::int64_t> asInteger() const;
  const std::string *asString() const;
  const Array *asArray() const;
  const Object *asObject() const;
  // The member `key` of an object, or nullptr.
  const Json *find(std::string_view key) const;
  // Appends a member to an object or an element to an array.
  void add(std::string key, Json value);
  void push(Json value);

  std::string dump() const;
  // nullopt unless `text` is exactly one valid JSON document in valid UTF-8.
  static std::optional<Json> parse(std::string_view text);

private:
  Type kind = Type::Null;
  bool flag = false;
  bool exact = false;
  std::int64_t whole = 0;
  double real = 0;
  std::string text;
  Array elements;
  Object members;
  void write(std::string &out) const;
};
} // namespace mettle::lsp
