#pragma once

#include "places/place.h"
#include "syntax/ast.h"
#include "types/type.h"
#include <cstdint>
#include <unordered_map>
#include <utility>

namespace mettle {
struct Flow {
  bool normal = true;
  bool returns = false;
  bool breaks = false;
  bool continues = false;
};
struct NodeFacts {
  Type type = Type::Unknown;
  int slot = -1;
  int callee = -1;
  int field = -1;
  bool constructor = false;
  bool method = false;
  bool receiverReservation = false;
  unsigned dereferences = 0;
  std::optional<Place> place;
  std::int32_t number = 0;
  bool foldedNegativeLiteral = false;
  std::vector<std::size_t> argumentOrder;
  Flow flow;
};
struct Local {
  std::string name;
  Type type;
  bool mutableBinding;
  Span span;
  ParameterMode mode = ParameterMode::Value;
};
struct FunctionFacts {
  Type result = Type::Unknown;
  bool diverges = false;
  std::vector<Local> locals;
  std::vector<std::size_t> resultSources;
};

class Checker;
class CheckedModule {
public:
  CheckedModule(CheckedModule &&) = default;
  CheckedModule &operator=(CheckedModule &&) = default;
  const Module &syntax() const { return tree; }
  const NodeFacts &facts(const Node &node) const { return nodes.at(&node); }
  const FunctionFacts &function(std::size_t index) const {
    return functions.at(index);
  }
  std::shared_ptr<const TypeStore> typeStore() const { return types; }

private:
  friend class Checker;
  explicit CheckedModule(Module module) : tree(std::move(module)) {}
  Module tree;
  std::unordered_map<const Node *, NodeFacts> nodes;
  std::vector<FunctionFacts> functions;
  std::shared_ptr<TypeStore> types = std::make_shared<TypeStore>();
};
} // namespace mettle
