#include "documentation/html.h"
#include "documentation/doctest.h"
#include "documentation/markdown.h"
#include "support/path.h"
#include <algorithm>
#include <map>
#include <set>
#include <string_view>
#include <utility>

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

using Links = std::map<std::string, std::string>;

bool pathChar(char c) {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
         (c >= '0' && c <= '9') || c == '_' || c == '.';
}

std::string linkedText(std::string_view text, const Links &links,
                       std::string_view page) {
  std::string out;
  for (std::size_t i = 0; i < text.size();) {
    if (!pathChar(text[i])) {
      put(out, text[i++]);
      continue;
    }
    auto end = i + 1;
    while (end < text.size() && pathChar(text[end]))
      ++end;
    while (end > i + 1 && text[end - 1] == '.')
      --end;
    auto name = std::string(text.substr(i, end - i));
    auto target = links.end();
    if (name.find('.') != std::string::npos) {
      target = links.find(name);
      if (target == links.end())
        target = links.find(std::string(page) + "." + name);
    }
    if (target != links.end() && !target->second.empty())
      out += "<a href=\"" + escape(target->second) + "\">" + escape(name) +
             "</a>";
    else
      out += escape(name);
    i = end;
  }
  return out;
}

// Text with `code` spans.
std::string inlineText(std::string_view text, const Links &links = {},
                       std::string_view page = {}) {
  std::string out;
  for (std::size_t i = 0; i < text.size(); ++i) {
    if (text[i] == '`') {
      auto close = text.find('`', i + 1);
      if (close != std::string_view::npos) {
        out += "<code>" +
               linkedText(text.substr(i + 1, close - i - 1), links, page) +
               "</code>";
        i = close;
        continue;
      }
    }
    auto end = text.find('`', i);
    if (end == std::string_view::npos)
      end = text.size();
    if (end == i) {
      put(out, text[i]);
      continue;
    }
    out += linkedText(text.substr(i, end - i), links, page);
    i = end - 1;
  }
  return out;
}

std::string joined(const std::vector<std::string> &lines, char separator) {
  std::string result;
  for (const auto &line : lines)
    result += (result.empty() ? "" : std::string(1, separator)) + line;
  return result;
}

std::string renderDoc(const Doc &doc, const Links &links,
                      std::string_view page) {
  std::string out;
  for (const auto &block : blocks(doc)) {
    switch (block.kind) {
    case Block::Kind::Paragraph:
      out += "<p>" + inlineText(joined(block.lines, ' '), links, page) +
             "</p>\n";
      break;
    case Block::Kind::Heading: {
      auto level = std::to_string(std::min(block.level + 3, 6u));
      out += "<h" + level + ">" +
             inlineText(block.lines.front(), links, page) + "</h" + level +
             ">\n";
      break;
    }
    case Block::Kind::List:
      out += "<ul>\n";
      for (const auto &entry : block.lines)
        out += "<li>" + inlineText(entry, links, page) + "</li>\n";
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
  PageWriter(const Page &page, std::string file, Links &links, bool collect)
      : page(page), file(std::move(file)), links(links), collect(collect) {}

  std::string render() {
    std::string out =
        "<!doctype html>\n<html lang=\"en\">\n<meta charset=\"utf-8\">\n"
        "<meta name=\"viewport\" content=\"width=device-width,"
        "initial-scale=1\">\n<title>" +
        escape(page.name) +
        "</title>\n<link rel=\"stylesheet\" href=\"style.css\">\n<main>\n"
        "<nav><a href=\"index.html\">All modules</a></nav>\n<h1>" +
        escape(page.name) + "</h1>\n<p class=\"src\">" + escape(page.path) +
        "</p>\n" + renderDoc(page.doc, links, page.name);
    items(out, page.items);
    return out + "</main>\n";
  }

private:
  const Page &page;
  std::string file;
  Links &links;
  bool collect;
  std::set<std::string> used;

  std::string identifier(std::string_view prefix, std::string_view name) {
    auto base =
        slug(prefix.empty() ? std::string(name)
                            : std::string(prefix) + "." + std::string(name));
    auto id = base;
    for (unsigned n = 2; !used.insert(id).second; ++n)
      id = base + "-" + std::to_string(n);
    if (collect) {
      auto key = page.name + "." +
                 (prefix.empty() ? std::string(name)
                                 : std::string(prefix) + "." +
                                       std::string(name));
      auto [it, inserted] = links.emplace(key, file + "#" + id);
      if (!inserted)
        it->second.clear();
    }
    return id;
  }

  std::string location(const Item &item) {
    return "<span class=\"src\">" + escape(page.path) + ":" +
           std::to_string(item.line) + "</span>";
  }

  std::string declaration(const Item &item) {
    std::string out = "<pre class=\"sig\"><code>";
    for (const auto &attribute : item.attributes)
      out += escape(attribute) + "\n";
    return out + linkedText(item.signature, links, page.name) +
           "</code></pre>\n";
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
           escape(item.kind == Kind::Implementation ? "extend" : item.name) +
           "</a><span class=\"kind\">" + std::string(word(item.kind)) +
           "</span>" + location(item) + "</h3>\n" + declaration(item) +
           renderDoc(item.doc, links, page.name);
    if (item.kind == Kind::Module) {
      out += "<div class=\"nested\">\n";
      items(out, item.members, id);
      out += "</div>\n";
    } else if (!item.members.empty()) {
      out += "<dl class=\"members\">\n";
      for (const auto &member : item.members) {
        auto memberId = identifier(id, member.name);
        out += "<dt id=\"" + memberId + "\"><code>" +
               linkedText(member.signature, links, page.name) +
               "</code></dt>\n<dd>" +
               renderDoc(member.doc, links, page.name) + "</dd>\n";
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
    if (c == '.') {
      base += '.';
    } else
      base += slug(std::string(1, c)) == "." ? '_' : c;
  }
  auto file = base + ".html";
  for (unsigned n = 2; !taken.insert(file).second; ++n)
    file = base + "-" + std::to_string(n) + ".html";
  return file;
}

std::string jsonString(std::string_view text) {
  static constexpr char hex[] = "0123456789abcdef";
  std::string out = "\"";
  for (unsigned char c : text) {
    if (c == '"' || c == '\\') {
      out += '\\';
      out += static_cast<char>(c);
    } else if (c < 0x20) {
      out += "\\u00";
      out += hex[c >> 4];
      out += hex[c & 15];
    } else {
      out += static_cast<char>(c);
    }
  }
  return out + '"';
}
} // namespace

std::vector<File> render(std::vector<Page> pages) {
  for (auto &page : pages)
    page.name = displayPath(page.name);
  std::stable_sort(pages.begin(), pages.end(),
                   [](const Page &left, const Page &right) {
                     return left.name < right.name;
                   });
  std::set<std::string> taken{"index.html"};
  Links links;
  std::vector<std::string> names;
  for (const auto &page : pages) {
    names.push_back(fileName(page.name, taken));
    auto [it, inserted] = links.emplace(page.name, names.back());
    if (!inserted)
      it->second.clear();
  }
  for (std::size_t i = 0; i < pages.size(); ++i)
    PageWriter(pages[i], names[i], links, true).render();
  std::string index =
      "<!doctype html>\n<html lang=\"en\">\n<meta charset=\"utf-8\">\n"
      "<meta name=\"viewport\" content=\"width=device-width,"
      "initial-scale=1\">\n<title>Documentation</title>\n"
      "<link rel=\"stylesheet\" href=\"style.css\">\n<main>\n"
      "<h1>Documentation</h1>\n"
      "<label>Search <input id=\"search\" type=\"search\"></label>\n"
      "<ul id=\"results\"></ul>\n<ul class=\"modules\">\n";
  std::vector<File> files;
  for (std::size_t i = 0; i < pages.size(); ++i) {
    const auto &page = pages[i];
    const auto &name = names[i];
    index += "<li><a href=\"" + name + "\"><code>" + escape(page.name) +
             "</code></a>";
    if (auto summary = firstSentence(page.doc); !summary.empty())
      index += "<span>" + inlineText(summary) + "</span>";
    index += "</li>\n";
    files.push_back({name, PageWriter(page, name, links, false).render()});
  }
  index += "</ul>\n</main>\n<script src=\"search-index.js\"></script>\n"
           "<script src=\"search.js\"></script>\n";
  std::string search = "[";
  for (const auto &[name, href] : links) {
    if (href.empty())
      continue;
    if (search.size() > 1)
      search += ',';
    search += "{\"name\":" + jsonString(name) + ",\"href\":" +
              jsonString(href) + "}";
  }
  search += "]\n";
  files.push_back({"search-index.json", search});
  files.push_back({"search-index.js", "const mettleSearch = " + search + ";\n"});
  files.push_back(
      {"search.js",
       "const input = document.getElementById('search');\n"
       "const results = document.getElementById('results');\n"
       "input.addEventListener('input', () => {\n"
       "  results.replaceChildren();\n"
       "  const query = input.value.trim().toLowerCase();\n"
       "  if (!query) return;\n"
       "  for (const item of mettleSearch) {\n"
       "    if (!item.name.toLowerCase().includes(query)) continue;\n"
       "    const li = document.createElement('li');\n"
       "    const link = document.createElement('a');\n"
       "    link.href = item.href; link.textContent = item.name;\n"
       "    li.append(link); results.append(li);\n"
       "  }\n"
       "});\n"});
  files.insert(files.begin(), File{"style.css", std::string(style)});
  files.insert(files.begin(), File{"index.html", std::move(index)});
  return files;
}
} // namespace mettle::documentation
