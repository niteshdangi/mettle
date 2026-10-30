#include "lsp/navigation.h"
#include "syntax/token.h"
#include <algorithm>
#include <set>

namespace mettle::lsp {
namespace {
const Declaration &declaration(const Files &files, std::size_t file, int id) {
  return files[file].index->declarations()[static_cast<std::size_t>(id)];
}
bool topLevel(const Files &files, std::size_t file, const Declaration &item) {
  return item.parent < 0 ||
         declaration(files, file, item.parent).kind == SymbolKind::Module;
}
bool validIdentifier(const std::string &name) {
  if (name.empty() || isReservedWord(name))
    return false;
  for (std::size_t i = 0; i < name.size(); ++i) {
    auto c = static_cast<unsigned char>(name[i]);
    bool letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                  c == '_' || c >= 0x80;
    if (!letter && !(i > 0 && c >= '0' && c <= '9'))
      return false;
  }
  return true;
}
// Declarations of `name` that are not locals or parameters, across the files.
std::size_t itemCount(const Files &files, const std::string &name) {
  std::size_t count = 0;
  for (const auto &file : files)
    for (const auto &item : file.index->declarations())
      if (!item.scoped() && item.kind != SymbolKind::Implementation &&
          item.name == name)
        ++count;
  return count;
}
std::string kindName(SymbolKind kind) {
  switch (kind) {
  case SymbolKind::Field:
    return "field";
  case SymbolKind::Variant:
    return "enumeration variant";
  case SymbolKind::Module:
    return "module";
  case SymbolKind::Implementation:
    return "implementation";
  default:
    return "function named main";
  }
}
} // namespace

const Declaration &declarationOf(const Files &files, Target target) {
  return declaration(files, target.file, target.declaration);
}

std::vector<Target> targetsAt(const Files &files, std::size_t file,
                              std::size_t offset) {
  const Occurrence *use = files[file].index->occurrenceAt(offset);
  if (!use || use->role == Role::Label)
    return {};
  if (use->role == Role::Declaration ||
      (use->role == Role::Lexical && use->declaration >= 0))
    return {{file, use->declaration}};
  std::vector<Target> found;
  bool sameFile = false;
  for (std::size_t g = 0; g < files.size(); ++g) {
    const auto &items = files[g].index->declarations();
    for (std::size_t d = 0; d < items.size(); ++d) {
      const auto &item = items[d];
      if (item.scoped() || item.kind == SymbolKind::Implementation ||
          item.name != use->name)
        continue;
      if (use->role == Role::Lexical && !topLevel(files, g, item))
        continue;
      found.push_back({g, static_cast<int>(d)});
      sameFile |= g == file;
    }
  }
  if (sameFile)
    std::erase_if(found, [&](Target target) { return target.file != file; });
  return found;
}

std::vector<Site> definitionsAt(const Files &files, std::size_t file,
                                std::size_t offset) {
  std::vector<Site> sites;
  for (auto target : targetsAt(files, file, offset)) {
    const auto &item = declarationOf(files, target);
    sites.push_back({target.file, item.nameBegin, item.nameEnd});
  }
  return sites;
}

std::optional<Hover> hoverAt(const Files &files, std::size_t file,
                             std::size_t offset) {
  const Occurrence *use = files[file].index->occurrenceAt(offset);
  auto targets = targetsAt(files, file, offset);
  if (!use || targets.empty())
    return std::nullopt;
  Hover hover;
  hover.range = {file, use->begin, use->end};
  for (std::size_t i = 0; i < targets.size(); ++i) {
    if (i > 0)
      hover.markdown += "\n\n";
    hover.markdown +=
        "```mettle\n" + declarationOf(files, targets[i]).signature + "\n```";
  }
  return hover;
}

RenamePlan planRename(const Files &files, std::size_t file, std::size_t offset,
                      const std::string &replacement) {
  RenamePlan plan;
  const Occurrence *use = files[file].index->occurrenceAt(offset);
  auto targets = targetsAt(files, file, offset);
  if (!use || targets.empty()) {
    plan.error = "no renameable symbol at this position";
    return plan;
  }
  if (targets.size() != 1) {
    plan.error = "'" + use->name + "' could refer to " +
                 std::to_string(targets.size()) + " declarations";
    return plan;
  }
  plan.name = {file, use->begin, use->end};
  plan.current = use->name;
  auto target = targets[0];
  const auto &item = declarationOf(files, target);
  if (item.kind == SymbolKind::Field || item.kind == SymbolKind::Variant ||
      item.kind == SymbolKind::Module ||
      item.kind == SymbolKind::Implementation ||
      (item.kind == SymbolKind::Function && item.name == "main")) {
    plan.error = "renaming a " + kindName(item.kind) + " is not supported";
    return plan;
  }
  if (!item.scoped() && itemCount(files, item.name) != 1) {
    plan.error = "'" + item.name +
                 "' is declared more than once, so its uses cannot be told "
                 "apart without type information";
    return plan;
  }
  if (replacement.empty())
    return plan;
  if (!validIdentifier(replacement)) {
    plan.error = "'" + replacement + "' is not a valid identifier";
    return plan;
  }
  std::set<Site> edits;
  if (item.scoped()) {
    for (const auto &occurrence : files[file].index->occurrences())
      if ((occurrence.role == Role::Declaration ||
           occurrence.role == Role::Lexical) &&
          occurrence.declaration == target.declaration)
        edits.insert(Site{file, occurrence.begin, occurrence.end});
    if (item.kind == SymbolKind::Parameter) {
      // Callers name the parameter in `name: value` arguments.
      const auto &function = declaration(files, file, item.owner);
      if (itemCount(files, function.name) != 1) {
        plan.error = "function '" + function.name +
                     "' is declared more than once, so named arguments of "
                     "its parameter cannot be updated";
        return plan;
      }
      for (std::size_t g = 0; g < files.size(); ++g)
        for (const auto &occurrence : files[g].index->occurrences()) {
          bool callee = occurrence.name == function.name &&
                        (occurrence.role == Role::Member ||
                         (occurrence.role == Role::Lexical &&
                          occurrence.declaration < 0));
          if (!callee)
            continue;
          for (const auto *label :
               files[g].index->argumentLabels(occurrence, item.name))
            edits.insert(Site{g, label->begin, label->end});
        }
    }
  } else {
    for (std::size_t g = 0; g < files.size(); ++g)
      for (const auto &occurrence : files[g].index->occurrences()) {
        if (occurrence.name != item.name)
          continue;
        bool declares = occurrence.role == Role::Declaration &&
                        !declaration(files, g, occurrence.declaration).scoped();
        bool uses = occurrence.role == Role::Member ||
                    (occurrence.role == Role::Lexical &&
                     occurrence.declaration < 0);
        if (declares || uses)
          edits.insert(Site{g, occurrence.begin, occurrence.end});
      }
  }
  plan.edits.assign(edits.begin(), edits.end());
  return plan;
}
} // namespace mettle::lsp
