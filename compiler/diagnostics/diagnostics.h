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

// Provenance of a compiler-generated source (an attribute expansion). Spans
// inside it map back to the user syntax that requested or shaped the code, so
// a diagnostic in generated code reports the offending user declaration and
// the attribute that generated it.
struct Generation {
  struct Mapping {
    std::size_t begin = 0, end = 0;
    Span target;
    // Unchanged text copied from `target`: positions inside keep their offset
    // and no generation note is printed.
    bool exact = false;
    // A mapping with its own provenance (a macro expansion) overrides the
    // generation's origin and description.
    Span origin{};
    std::string description{};
  };
  SourceId source = 0;
  Span origin;
  std::string description;
  std::vector<Mapping> mappings;
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
    // A repeated report of the same fault at the same place adds no
    // information.
    if (std::any_of(items.begin(), items.end(), [&](const Diagnostic &item) {
          return item.span.begin == span.begin && item.span.end == span.end &&
                 item.span.source == span.source && item.phase == phase &&
                 item.message == message;
        }))
      return;
    if (items.size() < limits::diagnostics)
      items.push_back({std::move(phase), span, std::move(message)});
    else
      ++suppressed;
  }
  void generated(Generation generation) {
    generations.push_back(std::move(generation));
  }
  bool empty() const { return items.empty(); }
  std::size_t count() const { return items.size() + suppressed; }
  void print(const Source &source, std::ostream &out) const {
    for (const auto &item : items) {
      auto generation = std::find_if(generations.begin(), generations.end(),
                                     [&](const Generation &entry) {
                                       return entry.source == item.span.source;
                                     });
      if (generation == generations.end()) {
        printItem(sourceOf(source, item.span), item.span.begin,
                  "error[" + item.phase + "]", item.message, out);
        continue;
      }
      auto target = generation->origin;
      auto origin = generation->origin;
      auto description = generation->description;
      bool exact = false;
      for (const auto &mapping : generation->mappings)
        if (mapping.begin <= item.span.begin && item.span.begin < mapping.end) {
          target = mapping.target;
          exact = mapping.exact;
          if (exact)
            target.begin += item.span.begin - mapping.begin;
          if (!mapping.description.empty()) {
            origin = mapping.origin;
            description = mapping.description;
          }
          break;
        }
      printItem(sourceOf(source, target), target.begin,
                "error[" + item.phase + "]", item.message, out);
      if (!exact && (target.begin != origin.begin ||
                     target.source != origin.source))
        printItem(sourceOf(source, origin), origin.begin, "note",
                  "in generated code for " + description, out);
    }
    if (suppressed)
      out << "mettle: " << suppressed
          << " additional diagnostics suppressed (limit " << limits::diagnostics
          << ")\n";
  }
  std::vector<Diagnostic> items;

private:
  SourceId currentSource = 0;
  std::size_t suppressed = 0;
  std::vector<Source> sources;
  std::vector<Generation> generations;
  const Source &sourceOf(const Source &fallback, Span span) const {
    auto found =
        std::find_if(sources.begin(), sources.end(), [&](const Source &entry) {
          return entry.id == span.source;
        });
    return found == sources.end() ? fallback : *found;
  }
  static void printItem(const Source &source, std::size_t position,
                        const std::string &label, const std::string &message,
                        std::ostream &out) {
    const auto offset = std::min(position, source.text.size());
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
    out << source.path << ':' << line << ':' << column << ": " << label << ": "
        << message << '\n'
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
