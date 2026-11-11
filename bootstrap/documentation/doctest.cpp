#include "documentation/doctest.h"
#include "documentation/markdown.h"
#include "support/path.h"
#include <algorithm>
#include <map>
#include <string_view>

namespace mettle::documentation {
Fence classify(const std::string &info) {
  Fence fence;
  bool ignore = false, fail = false, panic = false, skip = false;
  std::size_t i = 0;
  while (i < info.size()) {
    i = info.find_first_not_of(", \t", i);
    if (i == std::string::npos)
      break;
    auto end = info.find_first_of(", \t", i);
    if (end == std::string::npos)
      end = info.size();
    std::string_view word(info.data() + i, end - i);
    i = end;
    if (word == "mettle")
      continue;
    if (word == "ignore")
      ignore = true;
    else if (word == "no_run")
      skip = true;
    else if (word == "should_panic")
      panic = true;
    else if (word == "compile_fail")
      fail = true;
    else if (word.starts_with("compile_fail(") && word.ends_with(')')) {
      fail = true;
      fence.phase = std::string(word.substr(13, word.size() - 14));
    } else
      fence.mettle = false;
  }
  fence.mode = ignore  ? Mode::Ignore
               : fail  ? Mode::CompileFail
               : panic ? Mode::ShouldPanic
               : skip  ? Mode::NoRun
                       : Mode::Run;
  return fence;
}

bool hidden(const std::string &line) {
  return line == "~" || line.starts_with("~ ");
}

std::string unhidden(const std::string &line) {
  return hidden(line) ? (line.size() > 2 ? line.substr(2) : std::string())
                      : line;
}

namespace {
void fromDoc(const Doc &doc, const std::string &page, const std::string &owner,
             std::size_t insertion, std::vector<Example> &out) {
  for (const auto &block : blocks(doc)) {
    if (block.kind != Block::Kind::Code)
      continue;
    auto fence = classify(block.info);
    if (!fence.mettle)
      continue;
    Example example;
    example.insertion = insertion;
    example.mode = fence.mode;
    example.phase = fence.phase;
    example.line = block.numbers.empty() ? 0 : block.numbers.front();
    bool blank = true;
    for (const auto &line : block.lines) {
      auto code = unhidden(line);
      blank &= code.find_first_not_of(" \t") == std::string::npos;
      example.code += code + '\n';
    }
    if (blank)
      continue;
    example.name =
        page + " - " + owner + " (line " + std::to_string(example.line) + ")";
    out.push_back(std::move(example));
  }
}

void fromItem(const Item &item, const std::string &page,
              const std::string &prefix, std::size_t insertion,
              std::vector<Example> &out) {
  if (item.kind == Kind::Module && item.bodyEnd != std::string::npos)
    insertion = item.bodyEnd;
  auto owner =
      displayPath(prefix.empty() ? item.name : prefix + "::" + item.name);
  fromDoc(item.doc, page, owner, insertion, out);
  for (const auto &member : item.members)
    fromItem(member, page, owner, insertion, out);
}
} // namespace

std::vector<Example> examples(const Page &page) {
  std::vector<Example> result;
  fromDoc(page.doc, page.name, "(module)", std::string::npos, result);
  for (const auto &item : page.items)
    fromItem(item, page.name, "", std::string::npos, result);
  return result;
}

std::string testName(std::size_t index) {
  return "__doctest_" + std::to_string(index);
}

std::string withTests(const std::string &source,
                      const std::vector<Example> &examples,
                      const std::vector<std::size_t> &picks) {
  std::map<std::size_t, std::string> additions;
  for (auto index : picks) {
    const auto &example = examples[index];
    auto &result = additions[std::min(example.insertion, source.size())];
    result += '\n';
    // A block that declares its own `fn main()` becomes the test itself; the
    // items before it stay at the top level.
    std::size_t entry = 0;
    for (;; ++entry) {
      entry = example.code.find("fn main(", entry);
      if (entry == std::string::npos || entry == 0 ||
          example.code[entry - 1] == '\n')
        break;
    }
    bool program = entry != std::string::npos;
    if (program)
      result += example.code.substr(0, entry);
    result += "@test\n";
    if (example.mode == Mode::ShouldPanic)
      result += "@should_panic\n";
    else if (example.mode == Mode::NoRun)
      result += "@ignore(\"no_run\")\n";
    if (program)
      result += "fn " + testName(index) + "(" + example.code.substr(entry + 8);
    else
      result += "fn " + testName(index) + "() {\n" + example.code + "}\n";
  }
  std::string result = source;
  for (auto at = additions.rbegin(); at != additions.rend(); ++at)
    result.insert(at->first, at->second);
  return result;
}
} // namespace mettle::documentation
