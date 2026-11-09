#pragma once

#include "source/source.h"
#include <cstdint>
#include <string>
#include <vector>

namespace mettle::documentation {
// Documentation comment text (`///` and `//!` lines without the marker and
// one following space) with the source line of each line.
struct Doc {
  std::vector<std::string> lines;
  std::vector<std::size_t> numbers;
  std::vector<Span> spans;
  bool empty() const { return lines.empty(); }
};

enum class Kind {
  Function,
  Type,
  Union,
  Enum,
  Interface,
  Implementation,
  Module,
  Alias,
  Constant,
  Macro,
  Field,
  Variant
};

// One documented declaration. `signature` is the declaration header as
// written (whitespace collapsed, no body); `members` are the fields, variants
// and methods of a type, enum, interface or implementation, or the items of
// an inline module, in source order.
struct Item {
  Kind kind = Kind::Function;
  std::string name, signature;
  std::string canonical;
  Span span;
  std::uint32_t scope = 0;
  std::vector<std::string> attributes;
  Doc doc;
  std::size_t line = 0;
  std::vector<Item> members;
};

// The documentation of one source file: its `//!` text and its items in
// source order.
struct Page {
  std::string name, path;
  std::string canonical;
  Span span;
  std::uint32_t scope = 0;
  Doc doc;
  std::vector<Item> items;
};

// Reads the documentation of `source` from its token stream, so comments and
// signatures are exactly what was written. Public (`pub`) items are listed,
// plus private ones with `includePrivate`; fields, variants and the members of
// an interface or an interface implementation need no `pub`. `@test` and
// `@bench` functions are omitted. The caller has already established that the
// source parses.
Page extract(const Source &source, std::string name, bool includePrivate);
} // namespace mettle::documentation
