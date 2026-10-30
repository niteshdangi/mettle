#include "documentation/html.h"
#include "documentation/doctest.h"
#include "documentation/markdown.h"
#include <algorithm>
#include <set>
#include <string_view>

namespace mettle::documentation {
namespace {
constexpr std::string_view style =
    R"(:root{color-scheme:light dark;--fg:#1d1f21;--bg:#fff;--dim:#6b7280;--rule:#e5e7eb;--code:#f4f5f7;--accent:#b45309}
@media(prefers-color-scheme:dark){:root{--fg:#e5e7eb;--bg:#15171a;--dim:#9ca3af;--rule:#2a2e35;--code:#1e2227;--accent:#f59e0b}}
body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.6 system-ui,sans-serif}
main{max-width:50rem;margin:0 auto;padding:1.5rem 1.25rem 4rem}
a{color:inherit}nav{font-size:.9rem;color:var(--dim)}
h1{font-size:1.9rem;margin:.6rem 0}h2{margin:2.4rem 0 .4rem;padding-bottom:.2rem;border-bottom:1px solid var(--rule);font-size:1.25rem}
h3{display:flex;gap:.6rem;align-items:baseline;margin:1.8rem 0 .4rem;font-size:1.05rem}
h3 a{text-decoration:none;font-weight:600}
.kind{font-size:.72rem;letter-spacing:.06em;text-transform:uppercase;color:var(--accent)}
.src{margin-left:auto;font:.75rem ui-monospace,monospace;color:var(--dim)}
code,pre{font:.88rem/1.5 ui-monospace,SFMono-Regular,Menlo,monospace}
pre{background:var(--code);padding:.7rem .9rem;border-radius:6px;overflow-x:auto;margin:.4rem 0}
p code,li code,dt code{background:var(--code);padding:.05rem .3rem;border-radius:4px}
pre.sig{border-left:3px solid var(--accent)}
figure{margin:.6rem 0}figcaption{font-size:.72rem;color:var(--dim);text-transform:uppercase;letter-spacing:.06em}
dl.members{margin:.6rem 0 0 .2rem;padding-left:1rem;border-left:1px solid var(--rule)}
dt{margin-top:.7rem}dd{margin:0 0 0 1rem}
.nested{margin-left:1rem;padding-left:1rem;border-left:1px solid var(--rule)}
ul.modules{list-style:none;padding:0}ul.modules li{margin:.5rem 0}ul.modules span{color:var(--dim);margin-left:.6rem}
)";

void put(std::string &out, char c) {
  switch (c) {
  case '&':
    out += "&amp;";
    break;
  case '<':
    out += "&lt;";
    break;
  case '>':
    out += "&gt;";
    break;
  case '"':
    out += "&quot;";
    break;
  default:
    out += c;
  }
}

std::string escape(std::string_view text) {
  std::string out;
  for (char c : text)
    put(out, c);
  return out;
}

// Text with `code` spans.
std::string inlineText(std::string_view text) {
  std::string out;
  for (std::size_t i = 0; i < text.size(); ++i) {
    if (text[i] == '`') {
      auto close = text.find('`', i + 1);
      if (close != std::string_view::npos) {
        out += "<code>" + escape(text.substr(i + 1, close - i - 1)) + "</code>";
        i = close;
        continue;
      }
    }
    put(out, text[i]);
  }
  return out;
}

std::string joined(const std::vector<std::string> &lines, char separator) {
  std::string result;
  for (const auto &line : lines)
    result += (result.empty() ? "" : std::string(1, separator)) + line;
  return result;
}

std::string renderDoc(const Doc &doc) {
  std::string out;
  for (const auto &block : blocks(doc)) {
    switch (block.kind) {
    case Block::Kind::Paragraph:
      out += "<p>" + inlineText(joined(block.lines, ' ')) + "</p>\n";
      break;
    case Block::Kind::Heading: {
      auto level = std::to_string(std::min(block.level + 3, 6u));
      out += "<h" + level + ">" + inlineText(block.lines.front()) + "</h" +
             level + ">\n";
      break;
    }
    case Block::Kind::List:
      out += "<ul>\n";
      for (const auto &entry : block.lines)
        out += "<li>" + inlineText(entry) + "</li>\n";
      out += "</ul>\n";
      break;
    case Block::Kind::Code: {
      std::vector<std::string> shown;
      for (const auto &line : block.lines)
        if (!hidden(line))
          shown.push_back(line);
      auto fence = classify(block.info);
      bool plain =
          block.info.empty() || (fence.mettle && fence.mode == Mode::Run);
      out += "<figure>";
      if (!plain)
        out += "<figcaption>" + escape(block.info) + "</figcaption>";
      out += "<pre><code>" + escape(joined(shown, '\n')) + "</code></pre>" +
             "</figure>\n";
      break;
    }
    }
  }
  return out;
}

std::string firstSentence(const Doc &doc) {
  for (const auto &block : blocks(doc)) {
    if (block.kind != Block::Kind::Paragraph)
      continue;
    auto text = joined(block.lines, ' ');
    auto stop = text.find(". ");
    return stop == std::string::npos ? text : text.substr(0, stop + 1);
  }
  return {};
}

std::string_view word(Kind kind) {
  switch (kind) {
  case Kind::Function:
    return "function";
  case Kind::Type:
    return "type";
  case Kind::Union:
    return "union";
  case Kind::Enum:
    return "enum";
  case Kind::Interface:
    return "interface";
  case Kind::Implementation:
    return "implementation";
  case Kind::Module:
    return "module";
  case Kind::Alias:
    return "alias";
  case Kind::Constant:
    return "constant";
  case Kind::Macro:
    return "macro";
  case Kind::Field:
    return "field";
  case Kind::Variant:
    return "variant";
  }
  return {};
}

struct Section {
  std::string_view title;
  std::vector<Kind> kinds;
};

const std::vector<Section> &sections() {
  static const std::vector<Section> all{
      {"Modules", {Kind::Module}},
      {"Types", {Kind::Type, Kind::Union}},
      {"Enums", {Kind::Enum}},
      {"Interfaces", {Kind::Interface}},
      {"Functions", {Kind::Function}},
      {"Constants", {Kind::Constant}},
      {"Aliases", {Kind::Alias}},
      {"Macros", {Kind::Macro}},
      {"Implementations", {Kind::Implementation}}};
  return all;
}

std::string slug(std::string_view text) {
  std::string out;
  for (char c : text) {
    bool keep = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                (c >= '0' && c <= '9') || c == '_' || c == '-';
    out += keep ? c : '.';
  }
  return out;
}

class PageWriter {
public:
  explicit PageWriter(const Page &page) : page(page) {}

  std::string render() {
    std::string out =
        "<!doctype html>\n<html lang=\"en\">\n<meta charset=\"utf-8\">\n"
        "<meta name=\"viewport\" content=\"width=device-width,"
        "initial-scale=1\">\n<title>" +
        escape(page.name) +
        "</title>\n<link rel=\"stylesheet\" href=\"style.css\">\n<main>\n"
        "<nav><a href=\"index.html\">All modules</a></nav>\n<h1>" +
        escape(page.name) + "</h1>\n<p class=\"src\">" + escape(page.path) +
        "</p>\n" + renderDoc(page.doc);
    items(out, page.items);
    return out + "</main>\n";
  }

private:
  const Page &page;
  std::set<std::string> used;

  std::string identifier(std::string_view prefix, std::string_view name) {
    auto base =
        slug(prefix.empty() ? std::string(name)
                            : std::string(prefix) + "." + std::string(name));
    auto id = base;
    for (unsigned n = 2; !used.insert(id).second; ++n)
      id = base + "-" + std::to_string(n);
    return id;
  }

  std::string location(const Item &item) {
    return "<span class=\"src\">" + escape(page.path) + ":" +
           std::to_string(item.line) + "</span>";
  }

  static std::string declaration(const Item &item) {
    std::string out = "<pre class=\"sig\"><code>";
    for (const auto &attribute : item.attributes)
      out += escape(attribute) + "\n";
    return out + escape(item.signature) + "</code></pre>\n";
  }

  void items(std::string &out, const std::vector<Item> &all,
             const std::string &prefix = "") {
    for (const auto &section : sections()) {
      std::vector<const Item *> chosen;
      for (const auto &item : all)
        if (std::find(section.kinds.begin(), section.kinds.end(), item.kind) !=
            section.kinds.end())
          chosen.push_back(&item);
      if (chosen.empty())
        continue;
      std::stable_sort(chosen.begin(), chosen.end(),
                       [](const Item *left, const Item *right) {
                         return left->name < right->name;
                       });
      out += "<section>\n<h2>" + std::string(section.title) + "</h2>\n";
      for (const auto *item : chosen)
        entry(out, *item, prefix);
      out += "</section>\n";
    }
  }

  void entry(std::string &out, const Item &item, const std::string &prefix) {
    auto id = identifier(prefix, item.name);
    out += "<article id=\"" + id + "\">\n<h3><a href=\"#" + id + "\">" +
           escape(item.kind == Kind::Implementation ? "impl" : item.name) +
           "</a><span class=\"kind\">" + std::string(word(item.kind)) +
           "</span>" + location(item) + "</h3>\n" + declaration(item) +
           renderDoc(item.doc);
    if (item.kind == Kind::Module) {
      out += "<div class=\"nested\">\n";
      items(out, item.members, id);
      out += "</div>\n";
    } else if (!item.members.empty()) {
      out += "<dl class=\"members\">\n";
      for (const auto &member : item.members) {
        auto memberId = identifier(id, member.name);
        out += "<dt id=\"" + memberId + "\"><code>" + escape(member.signature) +
               "</code></dt>\n<dd>" + renderDoc(member.doc) + "</dd>\n";
      }
      out += "</dl>\n";
    }
    out += "</article>\n";
  }
};

std::string fileName(const std::string &name, std::set<std::string> &taken) {
  std::string base;
  for (std::size_t i = 0; i < name.size(); ++i) {
    char c = name[i];
    if (c == ':' && i + 1 < name.size() && name[i + 1] == ':') {
      base += '.';
      ++i;
    } else
      base += slug(std::string(1, c)) == "." ? '_' : c;
  }
  auto file = base + ".html";
  for (unsigned n = 2; !taken.insert(file).second; ++n)
    file = base + "-" + std::to_string(n) + ".html";
  return file;
}
} // namespace

std::vector<File> render(std::vector<Page> pages) {
  std::stable_sort(pages.begin(), pages.end(),
                   [](const Page &left, const Page &right) {
                     return left.name < right.name;
                   });
  std::set<std::string> taken{"index.html"};
  std::string index =
      "<!doctype html>\n<html lang=\"en\">\n<meta charset=\"utf-8\">\n"
      "<meta name=\"viewport\" content=\"width=device-width,"
      "initial-scale=1\">\n<title>Documentation</title>\n"
      "<link rel=\"stylesheet\" href=\"style.css\">\n<main>\n"
      "<h1>Documentation</h1>\n<ul class=\"modules\">\n";
  std::vector<File> files;
  for (const auto &page : pages) {
    auto name = fileName(page.name, taken);
    index += "<li><a href=\"" + name + "\"><code>" + escape(page.name) +
             "</code></a>";
    if (auto summary = firstSentence(page.doc); !summary.empty())
      index += "<span>" + inlineText(summary) + "</span>";
    index += "</li>\n";
    files.push_back({name, PageWriter(page).render()});
  }
  index += "</ul>\n</main>\n";
  files.insert(files.begin(), File{"style.css", std::string(style)});
  files.insert(files.begin(), File{"index.html", std::move(index)});
  return files;
}
} // namespace mettle::documentation
