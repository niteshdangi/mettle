#include "packages/semver.h"
#include <algorithm>
#include <cctype>

namespace mettle::packages {
namespace {
bool numeric(std::string_view text) {
  return !text.empty() &&
         std::all_of(text.begin(), text.end(),
                     [](unsigned char c) { return std::isdigit(c); });
}

std::optional<std::uint64_t> number(std::string_view text) {
  if (!numeric(text) || (text.size() > 1 && text[0] == '0') || text.size() > 19)
    return std::nullopt;
  std::uint64_t value = 0;
  for (char c : text)
    value = value * 10 + static_cast<std::uint64_t>(c - '0');
  return value;
}

std::vector<std::string_view> split(std::string_view text, char separator) {
  std::vector<std::string_view> parts;
  while (true) {
    auto cut = text.find(separator);
    parts.push_back(text.substr(0, cut));
    if (cut == std::string_view::npos)
      return parts;
    text.remove_prefix(cut + 1);
  }
}

bool identifiers(std::string_view text, bool tag) {
  for (auto part : split(text, '.')) {
    if (part.empty() ||
        !std::all_of(part.begin(), part.end(), [](unsigned char c) {
          return std::isalnum(c) || c == '-';
        }))
      return false;
    if (tag && numeric(part) && part.size() > 1 && part[0] == '0')
      return false;
  }
  return true;
}

// A possibly incomplete version as written in a requirement.
struct Partial {
  std::uint64_t major = 0, minor = 0, patch = 0;
  int count = 0;
  bool wildcard = false;
  std::vector<std::string> pre;
};

std::optional<Partial> parsePartial(std::string_view text) {
  Partial partial;
  auto plus = text.find('+');
  if (plus != std::string_view::npos)
    text = text.substr(0, plus);
  auto dash = text.find('-');
  std::string_view tag;
  if (dash != std::string_view::npos) {
    tag = text.substr(dash + 1);
    text = text.substr(0, dash);
    if (!identifiers(tag, true))
      return std::nullopt;
    for (auto part : split(tag, '.'))
      partial.pre.emplace_back(part);
  }
  auto parts = split(text, '.');
  if (parts.size() > 3 || (!tag.empty() && parts.size() != 3))
    return std::nullopt;
  std::uint64_t *fields[] = {&partial.major, &partial.minor, &partial.patch};
  for (std::size_t i = 0; i < parts.size(); ++i) {
    if (parts[i] == "*" || parts[i] == "x" || parts[i] == "X") {
      partial.wildcard = true;
      if (i == 0 && parts.size() == 1)
        return partial;
      if (i == 0 || i + 1 != parts.size())
        return std::nullopt;
      return partial;
    }
    auto value = number(parts[i]);
    if (!value)
      return std::nullopt;
    *fields[i] = *value;
    partial.count = static_cast<int>(i) + 1;
  }
  return partial;
}

Version versionOf(std::uint64_t major, std::uint64_t minor, std::uint64_t patch,
                  std::vector<std::string> pre = {}) {
  Version version;
  version.major = major;
  version.minor = minor;
  version.patch = patch;
  version.pre = std::move(pre);
  return version;
}

using Op = Comparator::Op;
Comparator bound(Op op, Version version, bool prerelease = false) {
  Comparator comparator;
  comparator.op = op;
  comparator.version = std::move(version);
  comparator.prerelease = prerelease;
  return comparator;
}

// First version above every version that shares the partial's components.
Version above(const Partial &p) {
  if (p.count <= 1)
    return versionOf(p.major + 1, 0, 0);
  return versionOf(p.major, p.minor + 1, 0);
}

bool expand(std::string_view text, std::vector<Comparator> &out,
            std::string &error) {
  auto trimmed = text;
  while (!trimmed.empty() && trimmed.front() == ' ')
    trimmed.remove_prefix(1);
  while (!trimmed.empty() && trimmed.back() == ' ')
    trimmed.remove_suffix(1);
  if (trimmed.empty()) {
    error = "empty version comparator";
    return false;
  }
  std::string_view op;
  for (auto candidate : {">=", "<=", ">", "<", "=", "^", "~"})
    if (trimmed.substr(0, std::string_view(candidate).size()) == candidate) {
      op = candidate;
      break;
    }
  auto rest = trimmed.substr(op.size());
  while (!rest.empty() && rest.front() == ' ')
    rest.remove_prefix(1);
  auto parsed = parsePartial(rest);
  if (!parsed) {
    error = "invalid version '" + std::string(rest) + "' in requirement";
    return false;
  }
  const auto &p = *parsed;
  bool tagged = !p.pre.empty();
  auto lower = versionOf(p.major, p.minor, p.patch, p.pre);
  if (p.count == 0 && op != ">=" && op != "" && op != "^" && op != "~" &&
      op != "=") {
    error = "wildcard requires an operator-free or '>=' form";
    return false;
  }
  if (op == "" || op == "^") {
    out.push_back(bound(Op::GreaterEqual, lower, tagged));
    if (p.count == 0)
      return true;
    Version upper;
    if (op.empty() && p.wildcard)
      upper = above(p);
    else if (p.major > 0)
      upper = versionOf(p.major + 1, 0, 0);
    else if (p.count == 1)
      upper = versionOf(1, 0, 0);
    else if (p.minor > 0)
      upper = versionOf(0, p.minor + 1, 0);
    else if (p.count == 2)
      upper = versionOf(0, 1, 0);
    else
      upper = versionOf(0, 0, p.patch + 1);
    out.push_back(bound(Op::Less, std::move(upper)));
  } else if (op == "~") {
    out.push_back(bound(Op::GreaterEqual, lower, tagged));
    if (p.count == 0)
      return true;
    out.push_back(bound(Op::Less, above(p)));
  } else if (op == "=") {
    if (p.count == 3) {
      out.push_back(bound(Op::Exact, lower, tagged));
    } else {
      out.push_back(bound(Op::GreaterEqual, lower));
      if (p.count > 0)
        out.push_back(bound(Op::Less, above(p)));
    }
  } else if (op == ">") {
    if (p.count == 3)
      out.push_back(bound(Op::Greater, lower, tagged));
    else
      out.push_back(bound(Op::GreaterEqual, above(p)));
  } else if (op == ">=") {
    out.push_back(bound(Op::GreaterEqual, lower, tagged));
  } else if (op == "<") {
    out.push_back(bound(Op::Less, lower, tagged));
  } else {
    if (p.count == 3)
      out.push_back(bound(Op::LessEqual, lower, tagged));
    else
      out.push_back(bound(Op::Less, above(p)));
  }
  return true;
}

bool holds(const Comparator &comparator, const Version &version) {
  int order = compare(version, comparator.version);
  switch (comparator.op) {
  case Op::Exact:
    return order == 0;
  case Op::Greater:
    return order > 0;
  case Op::GreaterEqual:
    return order >= 0;
  case Op::Less:
    return order < 0;
  case Op::LessEqual:
    return order <= 0;
  }
  return false;
}
} // namespace

std::optional<Version> parseVersion(std::string_view text) {
  Version version;
  auto plus = text.find('+');
  if (plus != std::string_view::npos) {
    auto build = text.substr(plus + 1);
    if (!identifiers(build, false))
      return std::nullopt;
    version.build = std::string(build);
    text = text.substr(0, plus);
  }
  auto dash = text.find('-');
  if (dash != std::string_view::npos) {
    auto tag = text.substr(dash + 1);
    if (!identifiers(tag, true))
      return std::nullopt;
    for (auto part : split(tag, '.'))
      version.pre.emplace_back(part);
    text = text.substr(0, dash);
  }
  auto parts = split(text, '.');
  if (parts.size() != 3)
    return std::nullopt;
  auto major = number(parts[0]), minor = number(parts[1]),
       patch = number(parts[2]);
  if (!major || !minor || !patch)
    return std::nullopt;
  version.major = *major;
  version.minor = *minor;
  version.patch = *patch;
  return version;
}

std::string toString(const Version &version) {
  std::string text = std::to_string(version.major) + '.' +
                     std::to_string(version.minor) + '.' +
                     std::to_string(version.patch);
  for (std::size_t i = 0; i < version.pre.size(); ++i)
    text += (i ? '.' : '-') + version.pre[i];
  if (!version.build.empty())
    text += '+' + version.build;
  return text;
}

int compare(const Version &left, const Version &right) {
  if (left.major != right.major)
    return left.major < right.major ? -1 : 1;
  if (left.minor != right.minor)
    return left.minor < right.minor ? -1 : 1;
  if (left.patch != right.patch)
    return left.patch < right.patch ? -1 : 1;
  if (left.pre.empty() != right.pre.empty())
    return left.pre.empty() ? 1 : -1;
  for (std::size_t i = 0; i < std::min(left.pre.size(), right.pre.size());
       ++i) {
    const auto &a = left.pre[i], &b = right.pre[i];
    bool aNumeric = numeric(a), bNumeric = numeric(b);
    if (aNumeric && bNumeric) {
      if (a.size() != b.size())
        return a.size() < b.size() ? -1 : 1;
      if (a != b)
        return a < b ? -1 : 1;
    } else if (aNumeric != bNumeric)
      return aNumeric ? -1 : 1;
    else if (a != b)
      return a < b ? -1 : 1;
  }
  if (left.pre.size() != right.pre.size())
    return left.pre.size() < right.pre.size() ? -1 : 1;
  return 0;
}

bool Requirement::matches(const Version &version) const {
  for (const auto &intersection : alternatives) {
    bool all =
        std::all_of(intersection.begin(), intersection.end(),
                    [&](const Comparator &c) { return holds(c, version); });
    if (!all)
      continue;
    if (version.pre.empty() ||
        std::any_of(intersection.begin(), intersection.end(),
                    [&](const Comparator &c) {
                      return c.prerelease && c.version.major == version.major &&
                             c.version.minor == version.minor &&
                             c.version.patch == version.patch;
                    }))
      return true;
  }
  return false;
}

std::optional<Requirement> parseRequirement(std::string_view text,
                                            std::string &error) {
  Requirement requirement;
  requirement.text = std::string(text);
  std::vector<Comparator> intersection;
  for (auto part : split(text, ','))
    if (!expand(part, intersection, error))
      return std::nullopt;
  requirement.alternatives.push_back(std::move(intersection));
  return requirement;
}

Requirement unite(std::vector<Requirement> parts) {
  Requirement united;
  for (std::size_t i = 0; i < parts.size(); ++i) {
    united.text += (i ? " || " : "") + parts[i].text;
    for (auto &alternative : parts[i].alternatives)
      united.alternatives.push_back(std::move(alternative));
  }
  return united;
}
} // namespace mettle::packages
