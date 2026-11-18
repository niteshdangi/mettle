#include "source/source.h"
#include "source/positions.h"
#include <algorithm>

namespace mettle {
SourceText::SourceText(SourceText &&other) noexcept
    : storage(std::move(other.storage)) {
  other.storage = std::string{};
}

SourceText &SourceText::operator=(SourceText &&other) noexcept {
  if (this != &other) {
    storage = std::move(other.storage);
    other.storage = std::string{};
  }
  return *this;
}

SourceText SourceText::retain(std::string_view text,
                              std::shared_ptr<const void> owner,
                              std::function<void(std::string_view)> validate) {
  if (!owner) {
    if (validate)
      validate(text);
    return SourceText(text);
  }
  SourceText result;
  result.storage = Retained{
      std::move(owner), text,
      validate ? std::make_shared<Validation>(std::move(validate)) : nullptr};
  return result;
}

std::string_view SourceText::bytes() const {
  if (const auto *owned = std::get_if<std::string>(&storage))
    return *owned;
  return std::get<Retained>(storage).text;
}

std::string_view SourceText::view() const {
  if (const auto *retained = std::get_if<Retained>(&storage);
      retained && retained->validation)
    std::call_once(retained->validation->once,
                   [&] { retained->validation->validate(retained->text); });
  return bytes();
}

std::string &SourceText::edit() {
  if (!std::holds_alternative<std::string>(storage))
    storage = std::string(view());
  return std::get<std::string>(storage);
}

SourceText &SourceText::operator+=(std::string_view text) {
  if (auto *owned = std::get_if<std::string>(&storage)) {
    owned->append(text);
  } else {
    std::string result(view());
    result.append(text);
    storage = std::move(result);
  }
  return *this;
}

namespace {
std::size_t width(std::string_view text, std::size_t offset) {
  auto byte = [&](std::size_t index) {
    return static_cast<unsigned char>(text[index]);
  };
  unsigned first = byte(offset);
  if (first < 128)
    return 1;
  unsigned count = first >= 0xc2 && first <= 0xdf   ? 2
                   : first >= 0xe0 && first <= 0xef ? 3
                   : first >= 0xf0 && first <= 0xf4 ? 4
                                                    : 0;
  if (!count || offset + count > text.size())
    return 0;
  for (unsigned i = 1; i < count; ++i)
    if ((byte(offset + i) & 0xc0) != 0x80)
      return 0;
  unsigned second = byte(offset + 1);
  if ((first == 0xe0 && second < 0xa0) || (first == 0xed && second >= 0xa0) ||
      (first == 0xf0 && second < 0x90) || (first == 0xf4 && second >= 0x90))
    return 0;
  return count;
}
} // namespace
SourcePositions::SourcePositions(std::string_view text) : size(text.size()) {
  for (std::size_t i = 0; i < text.size(); ++i) {
    auto byte = static_cast<unsigned char>(text[i]);
    bool crlf = byte == '\n' && i && text[i - 1] == '\r';
    if (byte == '\r' || (byte == '\n' && !crlf))
      lines.push_back(i + 1);
    else if (crlf || (byte & 0xc0) == 0x80)
      continuations.push_back(i);
  }
}

SourcePosition SourcePositions::position(std::size_t offset) const {
  offset = std::min(offset, size);
  auto line = std::upper_bound(lines.begin(), lines.end(), offset);
  auto start = *(line - 1);
  auto first =
      std::lower_bound(continuations.begin(), continuations.end(), start);
  auto last = std::lower_bound(first, continuations.end(), offset);
  return {static_cast<std::size_t>(line - lines.begin()),
          1 + offset - start - static_cast<std::size_t>(last - first)};
}

SourcePosition sourcePosition(const Source &source, std::size_t offset) {
  SourcePosition position{1, 1};
  for (std::size_t i = 0; i < offset && i < source.text.size(); ++i) {
    auto byte = static_cast<unsigned char>(source.text[i]);
    if (byte == '\r') {
      ++position.line;
      position.column = 1;
      if (i + 1 < source.text.size() && source.text[i + 1] == '\n')
        ++i;
    } else if (byte == '\n') {
      ++position.line;
      position.column = 1;
    } else if ((byte & 0xc0) != 0x80) {
      ++position.column;
    }
  }
  return position;
}
std::optional<std::size_t> invalidUtf8(std::string_view text) {
  for (std::size_t offset = 0; offset < text.size();) {
    auto count = width(text, offset);
    if (!count)
      return offset;
    offset += count;
  }
  return std::nullopt;
}
std::string printableUtf8(std::string_view text) {
  std::string result;
  for (std::size_t offset = 0; offset < text.size();) {
    auto count = width(text, offset);
    if (!count) {
      result += '?';
      ++offset;
    } else {
      result.append(text.substr(offset, count));
      offset += count;
    }
  }
  return result;
}
} // namespace mettle
