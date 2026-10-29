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
  class SourceContext {
  public:
    SourceContext(Diagnostics &diagnostics, const Source &source)
        : diagnostics(diagnostics), previous(diagnostics.currentSource) {
      diagnostics.currentSource = source.id;
      auto found = std::find_if(
          diagnostics.sources.begin(), diagnostics.sources.end(),
          [&](const Source &entry) { return entry.id == source.id; });
      if (found == diagnostics.sources.end())
        diagnostics.sources.push_back(source);
    }
    ~SourceContext() { diagnostics.currentSource = previous; }
    SourceContext(const SourceContext &) = delete;
    SourceContext &operator=(const SourceContext &) = delete;

  private:
    Diagnostics &diagnostics;
    SourceId previous;
  };
  void error(std::string phase, Span span, std::string message) {
    if (span.source == 0)
      span.source = currentSource;
    if (items.size() < limits::diagnostics)
      items.push_back({std::move(phase), span, std::move(message)});
  }
  bool empty() const { return items.empty(); }
  void print(const Source &source, std::ostream &out) const {
    for (const auto &item : items) {
      auto found = std::find_if(
          sources.begin(), sources.end(),
          [&](const Source &entry) { return entry.id == item.span.source; });
      const auto &selected = found == sources.end() ? source : *found;
      printItem(selected, item, out);
    }
  }
  std::vector<Diagnostic> items;

private:
  SourceId currentSource = 0;
  std::vector<Source> sources;
  static void printItem(const Source &source, const Diagnostic &item,
                        std::ostream &out) {
    const auto offset = std::min(item.span.begin, source.text.size());
    std::size_t line = 1, start = 0, column = 1;
    for (std::size_t i = 0; i < offset; ++i) {
      if (source.text[i] == '\n') {
        ++line;
        start = i + 1;
        column = 1;
      } else if ((static_cast<unsigned char>(source.text[i]) & 0xc0) != 0x80) {
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
};

} // namespace mettle
