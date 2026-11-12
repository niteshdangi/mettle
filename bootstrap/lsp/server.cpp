#include "lsp/server.h"
#include "diagnostics/diagnostics.h"
#include "expansion/macros.h"
#include "lsp/json.h"
#include "lsp/navigation.h"
#include "lsp/symbols.h"
#include "lsp/text.h"
#include "pipeline/compile.h"
#include "source/source.h"
#include "support/path.h"
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
constexpr std::size_t maxHeaders = 8u << 10;

std::string normalize(const std::string &path) {
  return std::filesystem::path(path).lexically_normal().generic_string();
}

std::string uriFromPath(const std::string &path) {
  constexpr char hex[] = "0123456789ABCDEF";
  std::string uri = "file://";
  for (unsigned char c : path) {
    if (c == ' ' || c == '#' || c == '?' || c == '%') {
      uri += '%';
      uri += hex[c >> 4];
      uri += hex[c & 0x0F];
    } else {
      uri += static_cast<char>(c);
    }
  }
  return uri;
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
  struct TypeFact {
    Span span;
    std::string display;
  };
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
  std::vector<TypeFact> typeFacts;
  SourceId sourceId = 0;
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
  std::map<std::string, std::unique_ptr<Document>> sourceDocuments;
  std::size_t openBytes = 0;
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
    std::size_t headerBytes = 0;
    for (char byte; in.get(byte);) {
      if (++headerBytes > maxHeaders)
        return std::nullopt;
      if (byte != '\n') {
        line += byte;
        continue;
      }
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
      line.clear();
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
               {"referencesProvider", Json::boolean(true)},
               {"documentSymbolProvider", Json::boolean(true)},
               {"completionProvider",
                Json::object(
                    {{"resolveProvider", Json::boolean(false)},
                     {"triggerCharacters", Json::array({Json::string(".")})}})},
               {"signatureHelpProvider",
                Json::object(
                    {{"triggerCharacters",
                      Json::array({Json::string("("), Json::string(",")})}})},
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
    auto found = documents.find(*uri);
    auto previous =
        found == documents.end() ? 0 : found->second->lines.contents().size();
    if (contents->size() > maxMessage - (openBytes - previous))
      return;
    auto &slot = documents[*uri];
    if (slot)
      slot->replace(*contents);
    else
      slot = std::make_unique<Document>(*uri, *contents);
    openBytes = openBytes - previous + contents->size();
    refresh(slot->path, slot.get());
  }

  void didChange(const Json *params) {
    auto *doc = find(params);
    const auto *changes = member(params, "contentChanges");
    if (!doc || !changes || !changes->asArray())
      return;
    auto before = doc->lines.contents();
    LineIndex current(before);
    for (const auto &change : *changes->asArray()) {
      const auto *replacement = text(change.find("text"));
      if (!replacement)
        continue;
      const auto *range = change.find("range");
      if (!range) {
        if (replacement->size() > maxMessage - (openBytes - before.size()))
          return;
        current = LineIndex(*replacement);
        continue;
      }
      auto begin = current.offset(positionOf(range->find("start")));
      auto end = current.offset(positionOf(range->find("end")));
      if (end < begin)
        std::swap(begin, end);
      auto edited = current.contents();
      if (replacement->size() > maxMessage - (openBytes - before.size() +
                                              edited.size() - (end - begin)))
        return;
      edited.replace(begin, end - begin, *replacement);
      current = LineIndex(std::move(edited));
    }
    if (doc->analyzed && current.contents() == before)
      return;
    openBytes = openBytes - before.size() + current.contents().size();
    doc->replace(current.contents());
    refresh(doc->path, doc);
  }

  void didClose(const Json *params) {
    auto *doc = find(params);
    if (!doc)
      return;
    auto uri = doc->uri;
    auto path = doc->path;
    openBytes -= doc->lines.contents().size();
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
    doc.index = SymbolIndex(doc.lines.contents());
    doc.typeFacts.clear();
    doc.sourceId = 0;
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
      if (tree) {
        for (const auto &source : diagnostics.registeredSources())
          if (normalize(source.path) == doc.path)
            doc.sourceId = source.id;
        pipeline::compile(
            std::move(*tree), diagnostics, false, config.target,
            [&](const CheckedModule &checked) {
              auto types = checked.typeStore();
              auto collectPattern = [&](auto &self, const Pattern &pattern,
                                        std::size_t scopeBegin,
                                        std::size_t scopeEnd) -> void {
                if (pattern.kind == PatternKind::Binding &&
                    pattern.span.source == doc.sourceId)
                  doc.index.addBinding(pattern.text, pattern.span, scopeBegin,
                                       scopeEnd);
                for (const auto &child : pattern.children)
                  self(self, child, scopeBegin, scopeEnd);
              };
              auto collect = [&](auto &self, const Node &node) -> void {
                auto *fact = checked.find(node);
                if (fact && fact->type != Type::Unknown)
                  doc.typeFacts.push_back(
                      {node.span, displayPath(types->name(fact->type))});
                auto bindDeclaration = [&](const std::string &name,
                                           std::size_t offset, SymbolKind kind,
                                           Span declarationSpan,
                                           const std::string &ownerName) {
                  if (declarationSpan.source != doc.sourceId)
                    return;
                  const auto &items = doc.index.declarations();
                  for (std::size_t i = 0; i < items.size(); ++i) {
                    const auto &item = items[i];
                    if (item.kind != kind || item.name != name ||
                        (kind != SymbolKind::Field &&
                         (item.nameBegin < declarationSpan.begin ||
                          item.nameBegin >= declarationSpan.end)))
                      continue;
                    if (kind == SymbolKind::Field) {
                      if (item.parent < 0 ||
                          static_cast<std::size_t>(item.parent) >= items.size())
                        continue;
                      auto owner =
                          items[static_cast<std::size_t>(item.parent)].name;
                      auto generic = owner.find('<');
                      if (generic != std::string::npos)
                        owner.resize(generic);
                      auto actual = ownerName;
                      generic = actual.find('<');
                      if (generic != std::string::npos)
                        actual.resize(generic);
                      auto dot = actual.rfind('.');
                      if (dot != std::string::npos)
                        actual = actual.substr(dot + 1);
                      if (owner != actual)
                        continue;
                    }
                    doc.index.bindOccurrence(offset, static_cast<int>(i));
                    break;
                  }
                };
                if (node.span.source == doc.sourceId &&
                    node.kind == Kind::Call && fact && fact->callee >= 0 &&
                    !node.children.empty() && node.children.front().get() &&
                    node.children.front().get()->kind == Kind::Field) {
                  const auto functionIndex =
                      static_cast<std::size_t>(fact->callee);
                  if (functionIndex < checked.syntax().functions.size()) {
                    const auto &function =
                        checked.syntax().functions[functionIndex];
                    const auto &member = *node.children.front().get();
                    auto offset = member.span.end >= member.text.size()
                                      ? member.span.end - member.text.size()
                                      : member.span.begin;
                    auto dot = function.name.rfind('.');
                    auto name = dot == std::string::npos
                                    ? function.name
                                    : function.name.substr(dot + 1);
                    bindDeclaration(name, offset, SymbolKind::Function,
                                    function.span, {});
                  }
                }
                if (node.span.source == doc.sourceId &&
                    node.kind == Kind::Field && fact && fact->field >= 0 &&
                    !node.children.empty() && node.children.front().get()) {
                  auto *receiver = checked.find(*node.children.front().get());
                  if (receiver) {
                    auto receiverType = receiver->type;
                    if (types->isView(receiverType))
                      receiverType = types->view(receiverType).payload;
                    if (types->isProduct(receiverType)) {
                      const auto &product = types->product(receiverType);
                      auto field = static_cast<std::size_t>(fact->field);
                      if (field < product.fields.size()) {
                        auto offset = node.span.end >= node.text.size()
                                          ? node.span.end - node.text.size()
                                          : node.span.begin;
                        bindDeclaration(product.fields[field].name, offset,
                                        SymbolKind::Field, node.span,
                                        displayPath(product.name));
                      }
                    }
                  }
                }
                if ((node.kind == Kind::If || node.kind == Kind::While) &&
                    node.children.size() >= 2) {
                  const auto &condition = *node.children[0];
                  if (condition.kind == Kind::ConditionChain) {
                    for (const auto &clause : condition.children)
                      for (const auto &pattern : clause->patterns)
                        collectPattern(collectPattern, pattern,
                                       clause->children[0]->span.end,
                                       node.children[1]->span.end);
                  } else
                    for (const auto &pattern : node.patterns)
                      collectPattern(collectPattern, pattern,
                                     node.children[1]->span.begin,
                                     node.children[1]->span.end);
                }
                if (node.kind == Kind::Arm)
                  for (const auto &pattern : node.patterns)
                    collectPattern(collectPattern, pattern, node.span.begin,
                                   node.span.end);
                if (node.kind == Kind::Closure)
                  for (const auto &parameter : node.parameters) {
                    if (parameter.pattern)
                      collectPattern(collectPattern, *parameter.pattern,
                                     node.span.begin, node.span.end);
                    else if (!parameter.name.empty() &&
                             parameter.span.source == doc.sourceId)
                      doc.index.addBinding(parameter.name, parameter.span,
                                           node.span.begin, node.span.end);
                  }
                for (const auto &child : node.children)
                  if (child.get())
                    self(self, *child.get());
              };
              for (std::size_t i = 0; i < checked.syntax().functions.size();
                   ++i) {
                const auto &function = checked.syntax().functions[i];
                if (function.body.get())
                  collect(collect, *function.body.get());
                if (function.span.source == doc.sourceId &&
                    function.annotation.empty()) {
                  auto result = checked.function(i).result;
                  if (result != Type::Unknown)
                    doc.index.setFunctionResult(
                        function.span, function.name,
                        displayPath(types->name(result)));
                }
              }
            },
            {}, config.numericEvaluator);
      }
    } catch (const std::exception &error) {
      diagnostics.error("internal", {}, error.what());
    }
    const auto &sources = diagnostics.registeredSources();
    doc.dependencies.clear();
    doc.sourceId = 0;
    for (const auto &source : sources) {
      auto path = normalize(source.path);
      doc.dependencies.insert(path);
      if (path == doc.path)
        doc.sourceId = source.id;
      if (path.empty() || path.front() != '/' || path == doc.path)
        continue;
      bool open = std::any_of(
          documents.begin(), documents.end(),
          [&](const auto &entry) { return entry.second->path == path; });
      if (open)
        continue;
      auto found = sourceDocuments.find(path);
      if (found == sourceDocuments.end())
        sourceDocuments.emplace(
            path, std::make_unique<Document>(uriFromPath(path), source.text));
      else if (found->second->lines.contents() != source.text)
        found->second->replace(source.text);
    }
    const std::string &contents = doc.lines.contents();
    auto list = Json::array();
    for (const auto &item : diagnostics.items) {
      const Source *where = nullptr;
      for (const auto &source : sources)
        if (source.id == item.span.source) {
          where = &source;
          break;
        }
      Span shown = item.span;
      if (diagnostics.isGenerated(item.span.source)) {
        shown = diagnostics.debugSpan(item.span);
        for (const auto &source : sources)
          if (source.id == shown.source) {
            where = &source;
            break;
          }
      }
      bool own =
          where ? normalize(where->path) == doc.path && where->text == contents
                : shown.source == doc.sourceId;
      std::size_t begin = 0, end = 0;
      std::string message = item.message;
      for (const auto &related : item.related)
        message += "\n" + related.kind + ": " + related.message;
      if (own) {
        begin = std::min(shown.begin, contents.size());
        end = std::clamp(shown.end, begin, contents.size());
        if (begin == end) {
          if (end < contents.size())
            end = nextCharacter(contents, end);
          else
            begin = previousCharacter(contents, begin);
        }
      } else if (where) {
        LineIndex other(where->text);
        auto [line, column] =
            other.lineColumn(std::min(shown.begin, where->text.size()));
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
    std::set<std::string> included;
    for (auto &entry : documents) {
      if (entry.second.get() == &current)
        result.current = result.documents.size();
      result.documents.push_back(entry.second.get());
      included.insert(entry.second->path);
      result.files.push_back(
          {entry.second->uri, &entry.second->lines, &entry.second->index});
    }
    for (const auto &entry : documents)
      for (const auto &path : entry.second->dependencies) {
        if (included.contains(path))
          continue;
        auto source = sourceDocuments.find(path);
        if (source == sourceDocuments.end())
          continue;
        included.insert(path);
        result.documents.push_back(source->second.get());
        result.files.push_back({source->second->uri, &source->second->lines,
                                &source->second->index});
      }
    return result;
  }
  static const Document::TypeFact *typeAt(const Document &doc,
                                          std::size_t offset) {
    const Document::TypeFact *result = nullptr;
    for (const auto &fact : doc.typeFacts)
      if (fact.span.source == doc.sourceId && fact.span.begin <= offset &&
          offset <= fact.span.end &&
          (!result || fact.span.end - fact.span.begin <
                          result->span.end - result->span.begin))
        result = &fact;
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
        "textDocument/references",     "textDocument/completion",
        "textDocument/signatureHelp",  "textDocument/rename",
        "textDocument/prepareRename"};
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
    } else if (method == "textDocument/completion") {
      auto space = workspace(*doc);
      respond(id, completion(space, *doc, at));
    } else if (method == "textDocument/signatureHelp") {
      auto space = workspace(*doc);
      respond(id, signatureHelp(space, *doc, at));
    } else if (method == "textDocument/hover") {
      auto space = workspace(*doc);
      auto hover = hoverAt(space.files, space.current, at);
      auto *inferred = typeAt(*doc, at);
      bool expressionHover = false;
      if (inferred && hover) {
        const auto *use = doc->index.occurrenceAt(at);
        auto targets = targetsAt(space.files, space.current, at);
        if (use && !targets.empty()) {
          const auto &target = declarationOf(space.files, targets.front());
          expressionHover = target.scoped() || target.kind == SymbolKind::Field;
        }
      }
      if (inferred && (!hover || expressionHover)) {
        auto value = Json::object(
            {{"kind", Json::string("markdown")},
             {"value",
              Json::string("```mettle\n" + inferred->display + "\n```")}});
        respond(id, Json::object(
                        {{"contents", std::move(value)},
                         {"range", rangeJson(doc->lines, inferred->span.begin,
                                             inferred->span.end)}}));
        return true;
      }
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
    } else if (method == "textDocument/references") {
      auto space = workspace(*doc);
      bool includeDeclaration = false;
      if (auto context = member(params, "context"))
        if (auto include = member(context, "includeDeclaration");
            include && include->asBoolean())
          includeDeclaration = *include->asBoolean();
      auto result = Json::array();
      for (const auto &site :
           referencesAt(space.files, space.current, at, includeDeclaration))
        result.push(location(space, site));
      respond(id, std::move(result));
    } else {
      rename(*doc, params, id, at, method == "textDocument/prepareRename");
    }
    return true;
  }

  static Json completion(const Workspace &space, const Document &doc,
                         std::size_t offset) {
    const auto &contents = doc.lines.contents();
    offset = std::min(offset, contents.size());
    auto prefixBegin = offset;
    while (prefixBegin > 0) {
      auto c = static_cast<unsigned char>(contents[prefixBegin - 1]);
      if (!(std::isalnum(c) || c == '_' || c >= 0x80))
        break;
      --prefixBegin;
    }
    auto prefix = contents.substr(prefixBegin, offset - prefixBegin);
    auto before = prefixBegin;
    while (before > 0 &&
           std::isspace(static_cast<unsigned char>(contents[before - 1])))
      --before;
    bool member = before > 0 && contents[before - 1] == '.';
    const Document::TypeFact *receiverType =
        member && before > 1 ? typeAt(doc, before - 2) : nullptr;
    auto shortType = [](std::string value) {
      while (!value.empty() &&
             std::isspace(static_cast<unsigned char>(value.front())))
        value.erase(value.begin());
      while (!value.empty() &&
             std::isspace(static_cast<unsigned char>(value.back())))
        value.pop_back();
      for (std::string_view mode : {"read ", "mut ", "take "})
        if (value.starts_with(mode)) {
          value.erase(0, mode.size());
          break;
        }
      auto generic = value.find('<');
      if (generic != std::string::npos)
        value.resize(generic);
      auto dot = value.rfind('.');
      return dot == std::string::npos ? value : value.substr(dot + 1);
    };
    std::set<std::string> emitted;
    auto result = Json::array();
    for (const auto *candidateDocument : space.documents) {
      const auto &items = candidateDocument->index.declarations();
      for (const auto &item : items) {
        if (item.kind == SymbolKind::Implementation ||
            (!prefix.empty() &&
             item.name.compare(0, prefix.size(), prefix) != 0))
          continue;
        bool candidate = !member
                             ? !item.scoped() || (candidateDocument == &doc &&
                                                  item.scopeBegin <= offset &&
                                                  offset < item.scopeEnd)
                         : receiverType ? item.kind == SymbolKind::Field ||
                                              item.kind == SymbolKind::Function
                                        : !item.scoped();
        if (candidate && member && receiverType && item.parent >= 0) {
          const auto &owner = items[static_cast<std::size_t>(item.parent)];
          std::string ownerName;
          if (item.kind == SymbolKind::Field)
            ownerName = owner.name;
          else if (owner.kind == SymbolKind::Implementation) {
            auto start = owner.signature.find("extend ");
            if (start != std::string::npos) {
              start += 7;
              auto end = owner.signature.find(" implements", start);
              if (end == std::string::npos)
                end = owner.signature.find('{', start);
              if (end != std::string::npos)
                ownerName = owner.signature.substr(start, end - start);
            }
          } else if (owner.kind == SymbolKind::Type ||
                     owner.kind == SymbolKind::Union)
            ownerName = owner.name;
          candidate = !ownerName.empty() &&
                      shortType(receiverType->display) == shortType(ownerName);
        } else if (candidate && member && receiverType && item.parent < 0) {
          candidate = false;
        }
        if (!candidate || !emitted.insert(item.name).second)
          continue;
        int kind = item.kind == SymbolKind::Field      ? 5
                   : item.kind == SymbolKind::Function ? 3
                   : item.scoped()                     ? 6
                                                       : 9;
        result.push(Json::object({{"label", Json::string(item.name)},
                                  {"kind", Json::integer(kind)},
                                  {"detail", Json::string(item.signature)}}));
      }
    }
    if (!member) {
      static constexpr std::string_view keywords[] = {
          "as",     "break", "const", "continue", "else",   "enum",
          "extend", "false", "fn",    "for",      "if",     "in",
          "let",    "loop",  "match", "module",   "return", "static",
          "true",   "type",  "var",   "while"};
      for (auto keyword : keywords)
        if ((prefix.empty() || keyword.substr(0, prefix.size()) == prefix) &&
            emitted.insert(std::string(keyword)).second)
          result.push(
              Json::object({{"label", Json::string(std::string(keyword))},
                            {"kind", Json::integer(14)}}));
    }
    return result;
  }

  static std::vector<std::string>
  signatureParameters(const std::string &signature) {
    auto open = signature.find('(');
    if (open == std::string::npos)
      return {};
    std::vector<std::string> result;
    std::size_t begin = open + 1;
    int depth = 0;
    for (std::size_t i = begin; i < signature.size(); ++i) {
      char c = signature[i];
      if (c == '(' || c == '[' || c == '<') {
        ++depth;
      } else if (c == ')' || c == ']' ||
                 (c == '>' && (i == 0 || signature[i - 1] != '-'))) {
        if (depth == 0) {
          if (i > begin)
            result.push_back(signature.substr(begin, i - begin));
          return result;
        }
        --depth;
      }
      if (c == ',' && depth == 0) {
        result.push_back(signature.substr(begin, i - begin));
        begin = i + 1;
      }
    }
    if (begin < signature.size())
      result.push_back(signature.substr(begin));
    return result;
  }

  static Json signatureHelp(const Workspace &space, const Document &doc,
                            std::size_t offset) {
    auto call = doc.index.callAt(offset);
    if (!call)
      return Json();
    std::vector<const Declaration *> candidates;
    for (const auto *candidateDocument : space.documents)
      for (const auto &item : candidateDocument->index.declarations())
        if (item.kind == SymbolKind::Function &&
            item.name == call->callee->name)
          candidates.push_back(&item);
    if (candidates.empty())
      return Json();
    auto signatures = Json::array();
    for (const auto *item : candidates) {
      auto parameters = signatureParameters(item->signature);
      auto label = item->signature;
      auto parameterInfo = Json::array();
      for (const auto &parameter : parameters)
        parameterInfo.push(Json::object({{"label", Json::string(parameter)}}));
      signatures.push(Json::object({{"label", Json::string(label)},
                                    {"parameters", std::move(parameterInfo)}}));
    }
    return Json::object(
        {{"signatures", std::move(signatures)},
         {"activeSignature", Json::integer(0)},
         {"activeParameter",
          Json::integer(static_cast<std::int64_t>(call->activeParameter))}});
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
