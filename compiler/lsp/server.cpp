#include "lsp/server.h"
#include "diagnostics/diagnostics.h"
#include "expansion/macros.h"
#include "lsp/json.h"
#include "lsp/navigation.h"
#include "lsp/symbols.h"
#include "lsp/text.h"
#include "pipeline/compile.h"
#include "source/source.h"
#include "syntax/format.h"
#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <exception>
#include <filesystem>
#include <istream>
#include <map>
#include <memory>
#include <optional>
#include <ostream>
#include <set>
#include <string_view>
#include <vector>

namespace mettle::lsp {
namespace {
constexpr int parseError = -32700, invalidRequest = -32600,
              methodNotFound = -32601, internalError = -32603,
              notInitialized = -32002, requestFailed = -32803;
constexpr std::size_t maxMessage = 64u << 20;

std::string normalize(const std::string &path) {
  return std::filesystem::path(path).lexically_normal().generic_string();
}

Json positionJson(Position position) {
  return Json::object(
      {{"line", Json::integer(static_cast<std::int64_t>(position.line))},
       {"character",
        Json::integer(static_cast<std::int64_t>(position.character))}});
}
Json rangeJson(const LineIndex &lines, std::size_t begin, std::size_t end) {
  return Json::object({{"start", positionJson(lines.position(begin))},
                       {"end", positionJson(lines.position(end))}});
}
const Json *member(const Json *value, std::string_view key) {
  return value ? value->find(key) : nullptr;
}
const std::string *text(const Json *value) {
  return value ? value->asString() : nullptr;
}
std::size_t nextCharacter(const std::string &s, std::size_t at) {
  ++at;
  while (at < s.size() && (static_cast<unsigned char>(s[at]) & 0xC0) == 0x80)
    ++at;
  return at;
}
std::size_t previousCharacter(const std::string &s, std::size_t at) {
  while (at > 0 && (static_cast<unsigned char>(s[--at]) & 0xC0) == 0x80) {
  }
  return at;
}

struct Document {
  Document(std::string documentUri, std::string contents)
      : uri(std::move(documentUri)), path(normalize(pathFromUri(uri))),
        lines(std::move(contents)), index(lines.contents()) {}
  void replace(std::string contents) {
    lines = LineIndex(std::move(contents));
    index = SymbolIndex(lines.contents());
  }
  std::string uri, path;
  LineIndex lines;
  SymbolIndex index;
  // Paths of every source the last analysis read, for incremental updates.
  std::set<std::string> dependencies;
  bool analyzed = false;
  std::string published;
};

int lspKind(const Declaration &item, const Declaration *parent) {
  switch (item.kind) {
  case SymbolKind::Function:
    return parent && parent->kind != SymbolKind::Function &&
                   parent->kind != SymbolKind::Module
               ? 6
               : 12;
  case SymbolKind::Type:
  case SymbolKind::Union:
    return 23;
  case SymbolKind::Enumeration:
    return 10;
  case SymbolKind::Interface:
    return 11;
  case SymbolKind::Alias:
    return 5;
  case SymbolKind::Static:
    return 13;
  case SymbolKind::Constant:
    return 14;
  case SymbolKind::Module:
    return 2;
  case SymbolKind::Implementation:
    return 3;
  case SymbolKind::Field:
    return 8;
  case SymbolKind::Variant:
    return 22;
  default:
    return 13;
  }
}

class Server {
public:
  Server(std::istream &input, std::ostream &output,
         const Configuration &configuration)
      : in(input), out(output), config(configuration) {}

  int run() {
    while (!exited) {
      auto body = read();
      if (!body)
        break;
      auto message = Json::parse(*body);
      if (!message) {
        fail(Json(), parseError, "invalid JSON");
        continue;
      }
      handle(*message);
    }
    return exited && shutdownSeen ? 0 : 1;
  }

private:
  std::istream &in;
  std::ostream &out;
  const Configuration &config;
  std::map<std::string, std::unique_ptr<Document>> documents;
  bool initialized = false, shutdownSeen = false, exited = false;

  struct Workspace {
    std::vector<Document *> documents;
    Files files;
    std::size_t current = 0;
  };

  std::optional<std::string> read() {
    std::size_t length = 0;
    bool framed = false;
    std::string line;
    while (std::getline(in, line)) {
      if (!line.empty() && line.back() == '\r')
        line.pop_back();
      if (line.empty()) {
        if (framed)
          break;
        continue;
      }
      std::string lower;
      for (char c : line)
        lower += static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
      constexpr std::string_view name = "content-length:";
      if (lower.compare(0, name.size(), name) == 0) {
        char *end = nullptr;
        auto value = std::strtoull(line.c_str() + name.size(), &end, 10);
        if (end == line.c_str() + name.size() || value > maxMessage)
          return std::nullopt;
        length = static_cast<std::size_t>(value);
        framed = true;
      }
    }
    if (!framed)
      return std::nullopt;
    std::string body(length, '\0');
    in.read(body.data(), static_cast<std::streamsize>(length));
    if (static_cast<std::size_t>(in.gcount()) != length)
      return std::nullopt;
    return body;
  }

  void send(const Json &message) {
    auto body = message.dump();
    out << "Content-Length: " << body.size() << "\r\n\r\n"
        << body << std::flush;
  }
  void respond(const Json &id, Json result) {
    send(Json::object({{"jsonrpc", Json::string("2.0")},
                       {"id", id},
                       {"result", std::move(result)}}));
  }
  void fail(const Json &id, int code, std::string message) {
    send(Json::object(
        {{"jsonrpc", Json::string("2.0")},
         {"id", id},
         {"error", Json::object({{"code", Json::integer(code)},
                                 {"message", Json::string(message)}})}}));
  }
  void notify(std::string method, Json params) {
    send(Json::object({{"jsonrpc", Json::string("2.0")},
                       {"method", Json::string(std::move(method))},
                       {"params", std::move(params)}}));
  }

  void handle(const Json &message) {
    if (!message.asObject()) {
      fail(Json(), invalidRequest, "a message must be an object");
      return;
    }
    const auto *method = text(message.find("method"));
    const Json *id = message.find("id");
    if (!method)
      return; // a response to a request this server never sent
    bool request = id && !id->isNull();
    try {
      if (*method == "exit") {
        exited = true;
      } else if (*method == "initialize") {
        initialized = true;
        if (request)
          respond(*id, initializeResult());
      } else if (!initialized) {
        if (request)
          fail(*id, notInitialized, "the server is not initialized");
      } else if (shutdownSeen) {
        if (request)
          fail(*id, invalidRequest, "the server is shut down");
      } else if (*method == "shutdown") {
        shutdownSeen = true;
        if (request)
          respond(*id, Json());
      } else if (*method == "textDocument/didOpen") {
        didOpen(message.find("params"));
      } else if (*method == "textDocument/didChange") {
        didChange(message.find("params"));
      } else if (*method == "textDocument/didClose") {
        didClose(message.find("params"));
      } else if (request) {
        if (!query(*method, message.find("params"), *id))
          fail(*id, methodNotFound, "unsupported method " + *method);
      }
    } catch (const std::exception &error) {
      if (request)
        fail(*id, internalError, error.what());
    }
  }

  Json initializeResult() {
    return Json::object(
        {{"capabilities",
          Json::object(
              {{"textDocumentSync",
                Json::object({{"openClose", Json::boolean(true)},
                              {"change", Json::integer(2)}})},
               {"hoverProvider", Json::boolean(true)},
               {"definitionProvider", Json::boolean(true)},
               {"documentSymbolProvider", Json::boolean(true)},
               {"documentFormattingProvider", Json::boolean(true)},
               {"renameProvider",
                Json::object({{"prepareProvider", Json::boolean(true)}})},
               {"positionEncoding", Json::string("utf-16")}})},
         {"serverInfo",
          Json::object({{"name", Json::string("mettle")},
                        {"version", Json::string(config.version)}})}});
  }

  Document *find(const Json *params) {
    const auto *uri = text(member(member(params, "textDocument"), "uri"));
    if (!uri)
      return nullptr;
    auto found = documents.find(*uri);
    return found == documents.end() ? nullptr : found->second.get();
  }

  void didOpen(const Json *params) {
    const auto *item = member(params, "textDocument");
    const auto *uri = text(member(item, "uri"));
    const auto *contents = text(member(item, "text"));
    if (!uri || !contents)
      return;
    auto &slot = documents[*uri];
    if (slot)
      slot->replace(*contents);
    else
      slot = std::make_unique<Document>(*uri, *contents);
    refresh(slot->path, slot.get());
  }

  void didChange(const Json *params) {
    auto *doc = find(params);
    const auto *changes = member(params, "contentChanges");
    if (!doc || !changes || !changes->asArray())
      return;
    auto before = doc->lines.contents();
    for (const auto &change : *changes->asArray()) {
      const auto *replacement = text(change.find("text"));
      if (!replacement)
        continue;
      const auto *range = change.find("range");
      if (!range) {
        doc->replace(*replacement);
        continue;
      }
      auto begin = doc->lines.offset(positionOf(range->find("start")));
      auto end = doc->lines.offset(positionOf(range->find("end")));
      if (end < begin)
        std::swap(begin, end);
      auto edited = doc->lines.contents();
      edited.replace(begin, end - begin, *replacement);
      doc->replace(std::move(edited));
    }
    if (doc->analyzed && doc->lines.contents() == before)
      return;
    refresh(doc->path, doc);
  }

  void didClose(const Json *params) {
    auto *doc = find(params);
    if (!doc)
      return;
    auto uri = doc->uri;
    auto path = doc->path;
    documents.erase(uri);
    notify("textDocument/publishDiagnostics",
           Json::object(
               {{"uri", Json::string(uri)}, {"diagnostics", Json::array()}}));
    refresh(path, nullptr);
  }

  static Position positionOf(const Json *value) {
    Position position;
    if (auto line = member(value, "line"); line && line->asInteger())
      position.line = static_cast<std::size_t>(
          std::max<std::int64_t>(0, *line->asInteger()));
    if (auto column = member(value, "character"); column && column->asInteger())
      position.character = static_cast<std::size_t>(
          std::max<std::int64_t>(0, *column->asInteger()));
    return position;
  }

  // Re-analyzes `first` and every other open document that read `changed`.
  void refresh(const std::string &changed, Document *first) {
    if (first)
      analyze(*first);
    for (auto &entry : documents)
      if (entry.second.get() != first &&
          entry.second->dependencies.contains(changed))
        analyze(*entry.second);
  }

  void analyze(Document &doc) {
    Diagnostics diagnostics;
    try {
      resolution::SourceProvider provider =
          [&](const std::string &requested) -> std::optional<Source> {
        auto path = normalize(requested);
        for (const auto &entry : documents)
          if (entry.second->path == path)
            return Source{path, entry.second->lines.contents()};
        if (config.provider)
          return config.provider(path);
        return std::nullopt;
      };
      auto tree = resolution::load(Source{doc.path, doc.lines.contents()},
                                   provider, diagnostics, config.library);
      if (tree)
        pipeline::compile(std::move(*tree), diagnostics, false, config.target);
    } catch (const std::exception &error) {
      diagnostics.error("internal", {}, error.what());
    }
    const auto &sources = diagnostics.registeredSources();
    doc.dependencies.clear();
    for (const auto &source : sources)
      doc.dependencies.insert(normalize(source.path));
    const std::string &contents = doc.lines.contents();
    auto list = Json::array();
    for (const auto &item : diagnostics.items) {
      const Source *where = nullptr;
      for (const auto &source : sources)
        if (source.id == item.span.source) {
          where = &source;
          break;
        }
      bool own =
          where ? normalize(where->path) == doc.path && where->text == contents
                : item.span.source == 0;
      std::size_t begin = 0, end = 0;
      std::string message = item.message;
      if (own) {
        begin = std::min(item.span.begin, contents.size());
        end = std::clamp(item.span.end, begin, contents.size());
        if (begin == end) {
          if (end < contents.size())
            end = nextCharacter(contents, end);
          else
            begin = previousCharacter(contents, begin);
        }
      } else if (where) {
        LineIndex other(where->text);
        auto [line, column] =
            other.lineColumn(std::min(item.span.begin, where->text.size()));
        message = where->path + ":" + std::to_string(line) + ":" +
                  std::to_string(column) + ": " + message;
        end = contents.empty() ? 0 : nextCharacter(contents, 0);
      }
      list.push(Json::object({{"range", rangeJson(doc.lines, begin, end)},
                              {"severity", Json::integer(1)},
                              {"code", Json::string(item.phase)},
                              {"source", Json::string("mettle")},
                              {"message", Json::string(message)}}));
    }
    auto dumped = list.dump();
    bool changed = !doc.analyzed || dumped != doc.published;
    doc.analyzed = true;
    doc.published = std::move(dumped);
    if (changed)
      notify("textDocument/publishDiagnostics",
             Json::object({{"uri", Json::string(doc.uri)},
                           {"diagnostics", std::move(list)}}));
  }

  Workspace workspace(Document &current) {
    Workspace result;
    for (auto &entry : documents) {
      if (entry.second.get() == &current)
        result.current = result.documents.size();
      result.documents.push_back(entry.second.get());
      result.files.push_back(
          {entry.second->uri, &entry.second->lines, &entry.second->index});
    }
    return result;
  }
  static Json location(const Workspace &space, const Site &site) {
    const auto *doc = space.documents[site.file];
    return Json::object(
        {{"uri", Json::string(doc->uri)},
         {"range", rangeJson(doc->lines, site.begin, site.end)}});
  }

  // Answers a request; false when the method is not supported.
  bool query(const std::string &method, const Json *params, const Json &id) {
    static const std::set<std::string> known = {
        "textDocument/hover",          "textDocument/definition",
        "textDocument/documentSymbol", "textDocument/formatting",
        "textDocument/rename",         "textDocument/prepareRename"};
    if (!known.contains(method))
      return false;
    auto *doc = find(params);
    if (!doc) {
      fail(id, invalidRequest, "the document is not open");
      return true;
    }
    auto at = doc->lines.offset(positionOf(member(params, "position")));
    if (method == "textDocument/documentSymbol") {
      respond(id, symbols(*doc));
    } else if (method == "textDocument/formatting") {
      respond(id, formatting(*doc));
    } else if (method == "textDocument/hover") {
      auto space = workspace(*doc);
      auto hover = hoverAt(space.files, space.current, at);
      if (!hover) {
        respond(id, Json());
        return true;
      }
      auto value = Json::object({{"kind", Json::string("markdown")},
                                 {"value", Json::string(hover->markdown)}});
      respond(id,
              Json::object({{"contents", std::move(value)},
                            {"range", rangeJson(doc->lines, hover->range.begin,
                                                hover->range.end)}}));
    } else if (method == "textDocument/definition") {
      auto space = workspace(*doc);
      auto result = Json::array();
      for (const auto &site : definitionsAt(space.files, space.current, at))
        result.push(location(space, site));
      respond(id, std::move(result));
    } else {
      rename(*doc, params, id, at, method == "textDocument/prepareRename");
    }
    return true;
  }

  void rename(Document &doc, const Json *params, const Json &id, std::size_t at,
              bool prepare) {
    auto space = workspace(doc);
    const auto *name = text(member(params, "newName"));
    if (!prepare && (!name || name->empty())) {
      fail(id, requestFailed, "the new name must not be empty");
      return;
    }
    auto plan = planRename(space.files, space.current, at,
                           prepare || !name ? std::string() : *name);
    if (!plan.error.empty()) {
      fail(id, requestFailed, plan.error);
      return;
    }
    if (prepare) {
      respond(id, Json::object({{"range", rangeJson(doc.lines, plan.name.begin,
                                                    plan.name.end)},
                                {"placeholder", Json::string(plan.current)}}));
      return;
    }
    auto changes = Json::object();
    std::size_t current = space.documents.size();
    Json edits;
    for (const auto &site : plan.edits) {
      if (site.file != current) {
        if (current != space.documents.size())
          changes.add(space.documents[current]->uri, std::move(edits));
        current = site.file;
        edits = Json::array();
      }
      edits.push(
          Json::object({{"range", rangeJson(space.documents[site.file]->lines,
                                            site.begin, site.end)},
                        {"newText", Json::string(*name)}}));
    }
    if (current != space.documents.size())
      changes.add(space.documents[current]->uri, std::move(edits));
    respond(id, Json::object({{"changes", std::move(changes)}}));
  }

  static Json symbols(const Document &doc) {
    const auto &items = doc.index.declarations();
    std::vector<std::vector<std::size_t>> children(items.size());
    std::vector<std::size_t> roots;
    for (std::size_t i = 0; i < items.size(); ++i) {
      if (items[i].scoped())
        continue;
      if (items[i].parent < 0)
        roots.push_back(i);
      else
        children[static_cast<std::size_t>(items[i].parent)].push_back(i);
    }
    auto build = [&](auto &self, std::size_t i) -> Json {
      const auto &item = items[i];
      const Declaration *parent =
          item.parent < 0 ? nullptr
                          : &items[static_cast<std::size_t>(item.parent)];
      auto begin = std::min(item.begin, item.nameBegin);
      auto end = std::max(item.end, item.nameEnd);
      auto nested = Json::array();
      for (auto child : children[i])
        nested.push(self(self, child));
      return Json::object({{"name", Json::string(item.name)},
                           {"detail", Json::string(item.signature)},
                           {"kind", Json::integer(lspKind(item, parent))},
                           {"range", rangeJson(doc.lines, begin, end)},
                           {"selectionRange",
                            rangeJson(doc.lines, item.nameBegin, item.nameEnd)},
                           {"children", std::move(nested)}});
    };
    auto result = Json::array();
    for (auto root : roots)
      result.push(build(build, root));
    return result;
  }

  static Json formatting(const Document &doc) {
    const std::string &contents = doc.lines.contents();
    Diagnostics diagnostics;
    std::optional<std::string> formatted;
    try {
      formatted = format(Source{doc.path, contents}, diagnostics,
                         [](const Source &input, Diagnostics &sink) {
                           SourceId next = input.id + 1;
                           return expansion::expandMacros(
                               input, sink, [&] { return next++; });
                         });
    } catch (const std::exception &) {
      return Json();
    }
    if (!formatted)
      return Json();
    auto edits = Json::array();
    if (*formatted != contents)
      edits.push(
          Json::object({{"range", rangeJson(doc.lines, 0, contents.size())},
                        {"newText", Json::string(*formatted)}}));
    return edits;
  }
};
} // namespace

int serve(std::istream &in, std::ostream &out,
          const Configuration &configuration) {
  return Server(in, out, configuration).run();
}
} // namespace mettle::lsp