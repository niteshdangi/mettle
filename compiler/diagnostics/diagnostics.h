#pragma once
#include "source/source.h"
#include "support/limits.h"
#include <algorithm>
#include <ostream>
#include <utility>
#include <vector>

namespace mettle {
struct Diagnostic {
  std::string phase;
  Span span;
  std::string message;
};

class Diagnostics {
public:
  void error(std::string phase, Span span, std::string message) {
    if (items.size() < limits::diagnostics)
      items.push_back({std::move(phase), span, std::move(message)});
  }
  bool empty() const { return items.empty(); }
  void print(const Source &source, std::ostream &out) const {
    for (const auto &item : items) {
      const auto offset = std::min(item.span.begin, source.text.size());
      std::size_t line = 1, start = 0, column = 1;
      for (std::size_t i = 0; i < offset; ++i) {
        if (source.text[i] == '\n') {
          ++line;
          start = i + 1;
          column = 1;
        } else if ((static_cast<unsigned char>(source.text[i]) & 0xc0) !=
                   0x80) {
          ++column;
        }
      }
      auto end = source.text.find('\n', start);
      if (end == std::string::npos)
        end = source.text.size();
      out << source.path << ':' << line << ':' << column << ": error["
          << item.phase << "]: " << item.message << '\n'
          << printableUtf8(
                 std::string_view(source.text).substr(start, end - start))
          << '\n';
      for (std::size_t i = start; i < offset; ++i)
        if ((static_cast<unsigned char>(source.text[i]) & 0xc0) != 0x80)
          out << (source.text[i] == '\t' ? '\t' : ' ');
      out << '^' << '\n';
    }
  }
  std::vector<Diagnostic> items;
};

} // namespace mettle
