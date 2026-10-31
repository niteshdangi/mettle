#include "semantics/checker.h"
#include <algorithm>
#include <array>

namespace mettle {
std::optional<int> Checker::operatorCall(Node &node, int left, int right,
                                         bool mutableIndex) {
  fields(false);
  auto self = inference.value(left);
  unsigned dereferences = 0;
  while (checked.types->isView(self)) {
    self = checked.types->view(self).payload;
    ++dereferences;
  }
  if (self == Type::Unknown || self == Type::Never || isNumeric(self) ||
      checked.types->isPointer(self) || self == Type::Bool ||
      self == Type::Char || self == Type::U8 || self == Type::Unit)
    return std::nullopt;
  struct Protocol {
    std::string_view token, interface, method;
  };
  static constexpr std::array protocols{
      Protocol{"+", "core::ops::Add", "add"},
      Protocol{"-", "core::ops::Sub", "sub"},
      Protocol{"*", "core::ops::Mul", "mul"},
      Protocol{"/", "core::ops::Div", "div"},
      Protocol{"%", "core::ops::Rem", "rem"},
      Protocol{"&", "core::ops::BitAnd", "bitand"},
      Protocol{"|", "core::ops::BitOr", "bitor"},
      Protocol{"^", "core::ops::BitXor", "bitxor"},
      Protocol{"<<", "core::ops::Shl", "shl"},
      Protocol{">>", "core::ops::Shr", "shr"},
      Protocol{"+=", "core::ops::AddAssign", "add_assign"},
      Protocol{"-=", "core::ops::SubAssign", "sub_assign"},
      Protocol{"*=", "core::ops::MulAssign", "mul_assign"},
      Protocol{"/=", "core::ops::DivAssign", "div_assign"},
      Protocol{"%=", "core::ops::RemAssign", "rem_assign"},
      Protocol{"&=", "core::ops::BitAndAssign", "bitand_assign"},
      Protocol{"|=", "core::ops::BitOrAssign", "bitor_assign"},
      Protocol{"^=", "core::ops::BitXorAssign", "bitxor_assign"},
      Protocol{"<<=", "core::ops::ShlAssign", "shl_assign"},
      Protocol{">>=", "core::ops::ShrAssign", "shr_assign"},
      Protocol{"==", "core::cmp::PartialEq", "eq"},
      Protocol{"!=", "core::cmp::PartialEq", "ne"},
      Protocol{"<", "core::cmp::PartialOrd", "lt"},
      Protocol{"<=", "core::cmp::PartialOrd", "le"},
      Protocol{">", "core::cmp::PartialOrd", "gt"},
      Protocol{">=", "core::cmp::PartialOrd", "ge"},
      Protocol{"[]", "core::ops::Index", "index"},
      Protocol{"[]mut", "core::ops::IndexMut", "index_mut"},
      Protocol{"[..]", "core::ops::IndexRange", "index_range"},
      Protocol{"[..]mut", "core::ops::IndexRangeMut", "index_range_mut"},
      Protocol{"negate", "core::ops::Neg", "neg"},
      Protocol{"!", "core::ops::Not", "not"}};
  const bool ranged = node.kind == Kind::Index && right < 0;
  auto token = ranged ? std::string_view(mutableIndex ? "[..]mut" : "[..]")
               : node.kind == Kind::Index
                   ? std::string_view(mutableIndex ? "[]mut" : "[]")
               : right < 0 && node.text == "-" ? std::string_view("negate")
                                               : std::string_view(node.text);
  auto protocol =
      std::find_if(protocols.begin(), protocols.end(),
                   [&](const auto &item) { return item.token == token; });
  if (protocol == protocols.end())
    return std::nullopt;
  auto interface = interfaceNames.find(std::string(protocol->interface));
  if (interface == interfaceNames.end()) {
    bool comparison = node.text == "==" || node.text == "!=" ||
                      node.text == "<" || node.text == "<=" ||
                      node.text == ">" || node.text == ">=";
    error("type", node.span,
          comparison
              ? "product comparisons require a declared comparison interface"
          : ranged ? "range indexing requires an array, slice or a type "
                     "implementing core.ops.IndexRange"
                   : "operator requires its native interface protocol");
    return inference.fresh();
  }
  const auto &definition =
      checked.interfaceData->definitions[interface->second];
  auto method = std::find_if(
      definition.methods.begin(), definition.methods.end(),
      [&](const auto &item) { return item.name == protocol->method; });
  if (method == definition.methods.end()) {
    error("type", node.span,
          "native operator interface has no required method");
    return inference.fresh();
  }
  ErasedType descriptor{definition.name,
                        static_cast<std::uint32_t>(interface->second)};
  if (!definition.parameters.empty() && right >= 0) {
    // `list[0]` is an unsuffixed integer. Built-in slices already demand
    // `usize`; a library Index impl should do the same when it is the
    // receiver's only integer index type. `value` would otherwise report i32.
    if ((token == "[]" || token == "[]mut") &&
        inference.unresolvedInteger(right)) {
      auto declaration = static_cast<std::uint32_t>(interface->second);
      Diagnostics ignored;
      interfaces::Solver solver(*checked.types, *checked.interfaceData, ignored,
                                interfaceAssumptions(), regionEnvironment());
      std::optional<Type> indexType;
      bool ambiguous = false;
      for (const auto &implementation :
           checked.interfaceData->implementations) {
        if (!checked.types->isErased(implementation.interfaceType))
          continue;
        const auto &erased =
            checked.types->erased(implementation.interfaceType);
        if (erased.declaration != declaration || erased.arguments.size() != 1)
          continue;
        auto bindings = solver.applicable(implementation, self, node.span);
        if (!bindings)
          continue;
        auto candidate =
            solver.normalize(erased.arguments[0], *bindings, node.span);
        if (!isInteger(candidate))
          continue;
        if (indexType && *indexType != candidate) {
          ambiguous = true;
          break;
        }
        indexType = candidate;
      }
      if (!ambiguous && indexType)
        inference.set(right, *indexType);
    }
    auto argument = inference.value(right);
    // A view operand compares through its payload like the receiver does.
    while (dereferences != 0 && checked.types->isView(argument))
      argument = checked.types->view(argument).payload;
    descriptor.arguments.push_back(argument);
  }
  if (definition.parameters.size() != descriptor.arguments.size()) {
    error("type", node.span,
          "native operator interface has incompatible parameters");
    return inference.fresh();
  }
  auto bound = checked.types->erasedType(std::move(descriptor));
  if (!interfaceObligation(self, bound, node.span))
    return inference.fresh();
  auto &callee = module.functions[method->function];
  auto &environment = functionGenerics.at(&callee);
  const auto count = ranged ? 3u : right < 0 ? 1u : 2u;
  if (callee.parameters.size() != count) {
    error("type", node.span, "native operator method has incompatible arity");
    return inference.fresh();
  }
  std::vector<TypeBinding> bindings{{environment.parameters[0], self}};
  const auto &arguments = checked.types->erased(bound).arguments;
  for (std::size_t p = 0; p < arguments.size(); ++p)
    bindings.push_back({environment.parameters[p + 1], arguments[p]});
  auto *saved = genericEnvironment;
  genericEnvironment = &environment;
  std::vector<Type> parameters;
  for (const auto &parameter : callee.parameters)
    parameters.push_back(
        annotation(parameter.annotation, parameter.span, callee.owner));
  completeGenericBindings(environment, bindings, node.span);
  auto declaredEffect =
      callee.error.empty()
          ? Type::Unknown
          : annotation(callee.error, callee.span, callee.owner);
  genericEnvironment = saved;
  auto result = normalizeGenericType(
      inference.value(functionVariables.at(&callee)), bindings, node.span);
  auto effect = declaredEffect == Type::Unknown
                    ? Type::Unknown
                    : normalizeGenericType(declaredEffect, bindings, node.span);
  for (auto &parameter : parameters)
    parameter = normalizeGenericType(parameter, bindings, node.span);
  genericObligations(environment, bindings, node.span);
  if (node.kind == Kind::Assign &&
      (callee.receiver != "mut" || result != Type::Unit))
    error("type", node.span,
          "compound assignment requires a mutable Unit-returning protocol");
  auto compare = node.text == "==" || node.text == "!=" || node.text == "<" ||
                 node.text == "<=" || node.text == ">" || node.text == ">=";
  if (compare && result != Type::Bool)
    error("type", node.span, "comparison protocol must return bool");
  if (right >= 0) {
    auto actual = inference.value(right);
    if (checked.types->isView(actual) &&
        checked.types->view(actual).payload == parameters[1] &&
        (callee.parameters[1].mode == "read" ||
         callee.parameters[1].mode == "mut"))
      actual = checked.types->view(actual).payload;
    coerce(*node.children[1], inference.fresh(actual),
           inference.fresh(parameters[1]), node.span);
  }
  auto &call = facts(node);
  call.typeArguments.clear();
  call.operatorCall = true;
  call.receiverReservation = callee.receiver == "mut";
  call.callee = method->function;
  call.interfaceSelf = self;
  call.interfaceType = bound;
  call.interfaceMethod = static_cast<int>(method - definition.methods.begin());
  call.dereferences = dereferences;
  call.callParameterTypes = std::move(parameters);
  call.effect = effect;
  call.callResult =
      effect == Type::Unknown
          ? result
          : checked.types->structural(AggregateKind::Outcome, {result, effect});
  for (auto parameter : environment.parameters) {
    auto found =
        std::find_if(bindings.begin(), bindings.end(), [&](auto binding) {
          return binding.parameter == parameter;
        });
    call.typeArguments.push_back(found == bindings.end() ? Type::Unknown
                                                         : found->argument);
  }
  if (effect != Type::Unknown && !effectContext)
    error("effects", node.span, "throwing operator requires try or capture");
  return inference.fresh(result);
}
void Checker::requireMutablePlace(Node &node) {
  auto &checkedNode = facts(node);
  checkedNode.exclusivePlace = true;
  if (node.kind == Kind::Index && checkedNode.indexView != Type::Unknown &&
      checked.types->view(checkedNode.indexView).mode != ParameterMode::Mut) {
    auto prior = checked.types->view(checkedNode.indexView).payload;
    auto key = node.children[1]->kind == Kind::Range
                   ? -1
                   : nodeVariables.at(node.children[1].get());
    auto result =
        operatorCall(node, nodeVariables.at(node.children[0].get()), key, true);
    auto view = result ? inference.value(*result) : Type::Unknown;
    if (!checked.types->isView(view) ||
        checked.types->view(view).mode != ParameterMode::Mut) {
      error("ownership", node.span,
            "mutable indexing requires a mutable-view IndexMut protocol");
      return;
    }
    inference.equal(inference.fresh(prior),
                    inference.fresh(checked.types->view(view).payload),
                    node.span);
    checkedNode.indexView = view;
    checkedNode.operatorCall = false;
  }
  if ((node.kind == Kind::Field || node.kind == Kind::Index ||
       node.kind == Kind::Group) &&
      !node.children.empty())
    requireMutablePlace(*node.children[0]);
}
} // namespace mettle
