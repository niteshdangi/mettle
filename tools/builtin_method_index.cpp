#include "packages/data.h"
#include "packages/sha256.h"
#include "resolution/load.h"
#include <fstream>
#include <iostream>
#include <iterator>
#include <map>
#include <string>

int main(int argc, char **argv) {
  if (argc != 3)
    return 1;
  std::map<std::string, std::string> digests;
  auto index = mettle::resolution::discoverBuiltinMethods(
      argv[1], [&](const std::string &path) -> std::optional<mettle::Source> {
        std::ifstream input(path, std::ios::binary);
        if (!input)
          return std::nullopt;
        std::string text((std::istreambuf_iterator<char>(input)), {});
        mettle::packages::Sha256 hash;
        hash.update(text);
        digests.emplace(path.substr(path.find_last_of('/') + 1), hash.finish());
        return mettle::Source{path, std::move(text)};
      });
  if (digests.size() != 4 || index.size() != digests.size()) {
    std::cerr << "cannot generate builtin method index from " << argv[1]
              << '\n';
    return 1;
  }
  std::ofstream out(argv[2], std::ios::binary | std::ios::trunc);
  out << "constexpr std::pair<std::string_view, std::string_view> "
         "builtinMethodDigests[]{\n";
  for (const auto &[name, hash] : digests)
    out << "    {\"" << name << "\", \"" << hash << "\"},\n";
  out << "};\nconstexpr char builtinMethodNames[] = R\"mettle({\n";
  for (const auto &[module, names] : index) {
    out << mettle::packages::data::quote(module) << ":[";
    for (const auto &name : names)
      out << mettle::packages::data::quote(name) << ',';
    out << "],\n";
  }
  out << "})mettle\";\n";
  out.close();
  if (!out)
    std::cerr << "cannot write builtin method index to " << argv[2] << '\n';
  return out ? 0 : 1;
}
