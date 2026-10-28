#pragma once

#include "syntax/token.h"
#include <memory>
#include <optional>
#include <utility>

namespace mettle {
struct Node;
class NodeOwner {
public:
  NodeOwner();
  NodeOwner(std::unique_ptr<Node> value);
  NodeOwner(NodeOwner &&) noexcept;
  NodeOwner &operator=(NodeOwner &&) noexcept;
  ~NodeOwner();
  Node *get() { return value.get(); }
  const Node *get() const { return value.get(); }
  Node &operator*() { return *value; }
  const Node &operator*() const { return *value; }
  Node *operator->() { return value.get(); }
  const Node *operator->() const { return value.get(); }

private:
  std::unique_ptr<Node> value;
};
enum class Kind {
  Integer,
  Boolean,
  Unit,
  Name,
  Group,
  Unary,
  Binary,
  Call,
  Block,
  If,
  Binding,
  Assign,
  Return,
  While,
  Loop,
  Break,
  Continue,
  Field
};
struct TypeSyntax {
  std::string name, view;
  std::vector<std::string> sources, regions;
  std::shared_ptr<const TypeSyntax> nested{};
  bool empty() const { return name.empty() && !nested; }
};
struct Node {
  Kind kind;
  Span span;
  std::string text;
  std::string name;
  TypeSyntax annotation;
  std::vector<NodeOwner> children;
  bool flag = false;
  bool semicolon = false;
  unsigned depth = 1;
};
inline NodeOwner::NodeOwner() = default;
inline NodeOwner::NodeOwner(std::unique_ptr<Node> node)
    : value(std::move(node)) {}
inline NodeOwner::NodeOwner(NodeOwner &&) noexcept = default;
inline NodeOwner &NodeOwner::operator=(NodeOwner &&) noexcept = default;
inline NodeOwner::~NodeOwner() = default;
struct Parameter {
  std::string name;
  TypeSyntax annotation;
  Span span;
  std::string mode{};
};
struct Function {
  std::string name;
  TypeSyntax annotation;
  Span span;
  std::vector<Parameter> parameters;
  NodeOwner body;
  std::string owner, receiver;
  bool destructor = false;
  std::vector<std::string> regions;
};
struct Module {
  std::vector<Token> tokens;
  std::vector<Function> functions;
  struct Product {
    std::string name;
    Span span;
    bool copyRequested = false;
    std::vector<Parameter> fields;
    std::vector<std::string> regions;
    std::vector<Function> methods;
    bool hasDestructor = false;
  };
  std::vector<Product> products;
};
std::optional<bool> booleanLiteral(const Node &node);
bool isStatement(Kind kind);
} // namespace mettle
