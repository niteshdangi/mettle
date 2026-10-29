#include "driver/inspect.h"
#include "syntax/lexer.h"
#include "syntax/parser.h"
#include "llvm/Support/JSON.h"
#include "llvm/Support/raw_ostream.h"

namespace mettle::driver {
namespace {
llvm::json::Value syntax(const mettle::Node &node) {
  llvm::json::Array children;
  for (const auto &child : node.children)
    children.push_back(syntax(*child));
  return llvm::json::Object{
      {"kind", static_cast<int>(node.kind)},
      {"text", node.text},
      {"label", node.label},
      {"begin", static_cast<std::int64_t>(node.span.begin)},
      {"end", static_cast<std::int64_t>(node.span.end)},
      {"semicolon", node.semicolon},
      {"children", std::move(children)}};
}
} // namespace
void inspect(const Module &tree) {
  llvm::json::Array tokens;
  for (const auto &token : tree.tokens)
    tokens.push_back(llvm::json::Object{
        {"kind", static_cast<int>(token.kind)},
        {"text", token.text},
        {"begin", static_cast<std::int64_t>(token.span.begin)},
        {"end", static_cast<std::int64_t>(token.span.end)}});
  llvm::json::Array functions;
  for (const auto &function : tree.functions)
    functions.push_back(llvm::json::Object{
        {"name", function.name},
        {"receiver", function.receiver},
        {"body", function.body.get() ? syntax(*function.body)
                                     : llvm::json::Value(nullptr)}});
  llvm::json::Array aliases;
  for (const auto &alias : tree.aliases)
    aliases.push_back(llvm::json::Object{{"name", alias.name},
                                         {"target", alias.target.name}});
  llvm::json::Array products;
  for (const auto &product : tree.products) {
    llvm::json::Array fields;
    for (const auto &field : product.fields)
      fields.push_back(llvm::json::Object{{"name", field.name},
                                          {"type", field.annotation.name}});
    products.push_back(llvm::json::Object{{"name", product.name},
                                          {"copy", product.copyRequested},
                                          {"fields", std::move(fields)}});
  }
  llvm::outs() << llvm::formatv(
      "{0:2}\n",
      llvm::json::Value(llvm::json::Object{{"tokens", std::move(tokens)},
                                           {"functions", std::move(functions)},
                                           {"aliases", std::move(aliases)},
                                           {"products", std::move(products)}}));
}
} // namespace mettle::driver
