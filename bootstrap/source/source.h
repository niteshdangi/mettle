#pragma once
#include <concepts>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <variant>
#include <vector>

namespace mettle {
using SourceId = std::uint32_t;
struct Span {
  std::size_t begin = 0;
  std::size_t end = 0;
  SourceId source = 0;
  bool operator==(const Span &) const = default;
};

struct SyntaxContext {
  std::vector<std::string> scope;
  Span definition;
  // Zero marks ordinary invocation syntax; an empty scope still names root.
  std::uint64_t identity = 0;
};
using SyntaxContextPtr = std::shared_ptr<const SyntaxContext>;

class SourceText {
public:
  SourceText() = default;
  SourceText(std::string text) : storage(std::move(text)) {}
  SourceText(std::string_view text) : storage(std::string(text)) {}
  SourceText(const char *text) : storage(std::string(text)) {}
  SourceText(const SourceText &) = default;
  SourceText &operator=(const SourceText &) = default;
  SourceText(SourceText &&other) noexcept;
  SourceText &operator=(SourceText &&other) noexcept;
  static SourceText retain(std::string_view text,
                           std::shared_ptr<const void> owner,
                           std::function<void(std::string_view)> validate = {});
  std::string_view view() const;
  operator std::string_view() const { return view(); }
  operator std::string() const { return std::string(view()); }
  const char *data() const { return view().data(); }
  std::size_t size() const { return bytes().size(); }
  bool empty() const { return size() == 0; }
  char operator[](std::size_t index) const { return view()[index]; }
  char &operator[](std::size_t index) { return edit()[index]; }
  std::string substr(std::size_t offset = 0,
                     std::size_t count = std::string_view::npos) const {
    return std::string(view().substr(offset, count));
  }
  std::size_t find(std::string_view text, std::size_t offset = 0) const {
    return view().find(text, offset);
  }
  std::size_t find(char text, std::size_t offset = 0) const {
    return view().find(text, offset);
  }
  SourceText &operator+=(std::string_view text);
  bool operator==(const SourceText &other) const {
    return view() == other.view();
  }
  template <typename Text>
    requires std::convertible_to<const Text &, std::string_view>
  bool operator==(const Text &other) const {
    return view() == std::string_view(other);
  }

private:
  struct Validation {
    explicit Validation(std::function<void(std::string_view)> validate)
        : validate(std::move(validate)) {}
    std::function<void(std::string_view)> validate;
    std::once_flag once;
  };
  struct Retained {
    std::shared_ptr<const void> owner;
    std::string_view text;
    std::shared_ptr<Validation> validation;
  };
  std::string_view bytes() const;
  std::string &edit();
  std::variant<std::string, Retained> storage;
};

struct Source {
  std::string path;
  SourceText text;
  SourceId id = 0;
};
struct SourcePosition {
  std::size_t line, column;
};
SourcePosition sourcePosition(const Source &source, std::size_t offset);

std::optional<std::size_t> invalidUtf8(std::string_view text);
std::string printableUtf8(std::string_view text);
} // namespace mettle
