#pragma once

#include "semantics/check.h"
#include "semantics/inference.h"

namespace mettle {
class Checker {
public:
  Checker(Module module, Diagnostics &diagnostics)
      : checked(std::move(module)), module(checked.tree),
        diagnostics(diagnostics), inference(diagnostics, *checked.types) {}
  std::optional<CheckedModule> run();

private:
  struct Binding {
    int variable;
    int slot;
  };
  CheckedModule checked;
  Module &module;
  Diagnostics &diagnostics;
  TypeInference inference;
  std::unordered_map<std::string, std::size_t> names;
  std::unordered_map<std::string, Type> typeNames{{"i32", Type::I32},
                                                  {"bool", Type::Bool},
                                                  {"Unit", Type::Unit},
                                                  {"Never", Type::Never}};
  std::vector<std::unordered_map<std::string, Binding>> scopes;
  std::unordered_map<Function *, std::vector<int>> localVariables;
  std::unordered_map<const Function *, int> functionVariables;
  std::unordered_map<const Node *, int> nodeVariables;
  Function *current = nullptr;
  unsigned loops = 0;
  std::vector<std::pair<int, Span>> integerOrBoolean;
  std::vector<std::pair<int, Span>> comparisons;
  struct FieldRequest {
    Node *node;
    int base, result;
    bool resolved = false;
  };
  std::vector<FieldRequest> fieldRequests;

  NodeFacts &facts(const Node &node) { return checked.nodes[&node]; }
  FunctionFacts &facts(const Function &function) {
    return checked.functions.at(
        static_cast<std::size_t>(&function - module.functions.data()));
  }
  void error(std::string phase, Span span, std::string message);
  Type annotation(const TypeSyntax &syntax, Span span,
                  std::string_view owner = {});
  Binding lookup(const std::string &name, Span span);
  int local(std::string name, int variable, bool mutableBinding, Span span);
  Flow flow(Node &node);
  void literal(Node &node, bool negative = false);
  void function(Function &function);
  int node(Node &node, bool reachable);
  int call(Node &node, bool reachable);
  void products();
  void fields(bool final = true);
};
} // namespace mettle
