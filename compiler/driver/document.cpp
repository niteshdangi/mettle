#include "driver/document.h"
#include "documentation/html.h"
#include "expansion/macros.h"
#include "syntax/parser.h"
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <set>

namespace mettle::driver {
namespace {
namespace fs = std::filesystem;

struct Input {
  fs::path file;
  std::string name;
};

// A page is named by its path below the given directory: `net/http.mt` is
// `net::http` and a directory's `module.mt` names the directory itself.
std::string pageName(const fs::path &relative) {
  auto stem = relative;
  stem.replace_extension();
  if (stem.filename() == "module" && stem.has_parent_path())
    stem = stem.parent_path();
  std::string name;
  for (const auto &part : stem)
    name += (name.empty() ? "" : "::") + part.generic_string();
  return name;
}

bool gather(const std::string &argument, std::vector<Input> &inputs) {
  std::error_code error;
  fs::path path(argument);
  if (fs::is_directory(path, error)) {
    std::vector<Input> found;
    for (fs::recursive_directory_iterator walk(path, error), end;
         !error && walk != end; walk.increment(error)) {
      auto name = walk->path().filename().string();
      if (walk->is_directory(error) &&
          (name == "target" || name.starts_with("."))) {
        walk.disable_recursion_pending();
        continue;
      }
      if (walk->is_regular_file(error) && walk->path().extension() == ".mt")
        found.push_back(
            {walk->path(), pageName(fs::relative(walk->path(), path))});
    }
    if (error) {
      std::cerr << "mettle: error[io]: cannot read " << argument << ": "
                << error.message() << '\n';
      return false;
    }
    inputs.insert(inputs.end(), found.begin(), found.end());
    return true;
  }
  if (!fs::is_regular_file(path, error)) {
    std::cerr << "mettle: error[io]: cannot read " << argument << '\n';
    return false;
  }
  inputs.push_back({path, pageName(path.filename())});
  return true;
}

bool write(const fs::path &path, const std::string &content) {
  std::ofstream out(path, std::ios::binary | std::ios::trunc);
  out << content;
  out.flush();
  return static_cast<bool>(out);
}
} // namespace

int document(const Options &options) {
  std::vector<std::string> arguments{options.input};
  arguments.insert(arguments.end(), options.moreInputs.begin(),
                   options.moreInputs.end());
  std::vector<Input> inputs;
  int status = 0;
  for (const auto &argument : arguments)
    if (!gather(argument, inputs))
      status = 1;
  std::stable_sort(
      inputs.begin(), inputs.end(), [](const Input &left, const Input &right) {
        return left.file.generic_string() < right.file.generic_string();
      });
  std::vector<documentation::Page> pages;
  std::set<std::string> seen;
  for (const auto &input : inputs) {
    auto display = input.file.lexically_normal().generic_string();
    if (!seen.insert(display).second)
      continue;
    std::ifstream in(input.file, std::ios::binary);
    std::string text((std::istreambuf_iterator<char>(in)),
                     std::istreambuf_iterator<char>());
    if (!in && !in.eof()) {
      std::cerr << "mettle: error[io]: cannot read " << display << '\n';
      status = 1;
      continue;
    }
    // Documentation is published only for a source that parses.
    Source source{display, text};
    Diagnostics diagnostics;
    SourceId next = source.id + 1;
    auto expanded = expansion::expandMacros(source, diagnostics,
                                            [&] { return next++; });
    parse(expanded ? *expanded : source, diagnostics);
    if (!diagnostics.empty()) {
      diagnostics.print(source, std::cerr);
      status = 1;
      continue;
    }
    pages.push_back(documentation::extract(source, input.name,
                                           options.documentPrivate));
  }
  fs::path directory = options.output;
  if (directory.empty()) {
    std::error_code error;
    auto base = fs::is_directory(options.input, error) &&
                        options.moreInputs.empty()
                    ? fs::path(options.input)
                    : fs::path();
    directory = base / "target" / "mettle" / "doc";
  }
  std::error_code error;
  fs::create_directories(directory, error);
  if (error) {
    std::cerr << "mettle: error[io]: cannot create " << directory.string()
              << ": " << error.message() << '\n';
    return 1;
  }
  for (const auto &file : documentation::render(pages))
    if (!write(directory / file.name, file.content)) {
      std::cerr << "mettle: error[io]: cannot write "
                << (directory / file.name).string() << '\n';
      return 1;
    }
  std::cout << "mettle: documented " << pages.size()
            << (pages.size() == 1 ? " module" : " modules") << " into "
            << (directory / "index.html").generic_string() << '\n';
  return status;
}
} // namespace mettle::driver
