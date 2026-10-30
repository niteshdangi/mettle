#include "lowering/builder.h"
#include <functional>
#include <set>

namespace mettle::lowering {
using ir::Exit;
using ir::Op;

int Builder::defaultIndex(std::size_t callee, std::size_t parameter) const {
  std::size_t result = module.syntax().functions.size();
  for (std::size_t f = 0; f < module.syntax().functions.size(); ++f)
    for (std::size_t p = 0; p < module.syntax().functions[f].parameters.size();
         ++p)
      if (module.syntax().functions[f].parameters[p].defaultValue.get()) {
        if (f == callee && p == parameter)
          return static_cast<int>(result);
        ++result;
      }
  throw std::runtime_error("missing checked parameter default");
}

ir::Function Builder::runDefault(const mettle::Function &source,
                                 std::size_t index, std::size_t parameter) {
  const auto &checked = module.function(index);
  const auto &body = *source.parameters[parameter].defaultValue;
  function = {checked.canonicalName + ".<default." + std::to_string(parameter) +
                  ">",
              checked.defaultAbiResults[parameter],
              parameter,
              {},
              {},
              0};
  errorType = checked.error;
  function.genericParameters = checked.genericParameters;
  function.floatingPolicy = checked.floatingPolicy;
  function.interfaceBounds = checked.interfaceBounds;
  function.unpinBounds = checked.unpinBounds;
  function.regionSignature = checked.regionSignature;
  function.genericEqualities = checked.genericEqualities;
  function.targetFeatures = checked.targetFeatures;
  function.unsafeFunction = source.unsafeFunction;
  unsafeDepth = source.unsafeFunction ? 1 : 0;
  for (std::size_t i = 0; i < checked.locals.size(); ++i) {
    const auto &local = checked.locals[i];
    auto mode = i < parameter
                    ? (local.mode == ParameterMode::Mut ? ParameterMode::Mut
                                                        : ParameterMode::Read)
                : i < source.parameters.size() ? ParameterMode::Value
                                               : local.mode;
    function.locals.push_back(
        {local.name, local.type, local.mutableBinding, local.span, mode,
         i < parameter ? 0 : -1,
         i < parameter ? static_cast<std::uint32_t>(i) : 0, local.storage,
         local.staticIndex});
  }
  function.twoPhaseReceiver = source.receiver == "mut" && parameter != 0;
  if (module.typeStore()->containsViews(function.result)) {
    std::set<std::size_t> sources;
    std::function<void(const Node &)> referenced = [&](const Node &node) {
      if (auto slot = module.facts(node).slot;
          node.kind == Kind::Name && slot >= 0) {
        if (static_cast<std::size_t>(slot) < parameter)
          sources.insert(static_cast<std::size_t>(slot));
        else if (auto found = checked.parameterBindings.find(slot);
                 found != checked.parameterBindings.end() &&
                 found->second < parameter)
          sources.insert(found->second);
      }
      for (const auto &child : node.children)
        referenced(*child);
    };
    referenced(body);
    function.resultSources.assign(sources.begin(), sources.end());
  }
  order = static_cast<std::uint32_t>(parameter);
  current = block();
  for (std::size_t i = 0; i < parameter; ++i)
    if (source.parameters[i].pattern) {
      auto mode = function.locals[i].mode;
      auto type = function.locals[i].type;
      Place place{static_cast<int>(i), {}};
      while (module.typeStore()->isView(type)) {
        const auto &view = module.typeStore()->view(type);
        mode = mode == ParameterMode::Read ? ParameterMode::Read : view.mode;
        type = view.payload;
        place.fields.push_back(Projection::dereference());
      }
      std::function<void(const Pattern &)> aliases = [&](const Pattern &p) {
        auto slot = module.facts(p).slot;
        if (slot >= 0 && !localRemap.contains(slot)) {
          if (function.locals.size() >= limits::locals)
            throw LoweringLimit("parameter pattern local limit exceeded");
          auto local = checked.locals[slot];
          auto views = checked.parameterViewTypes.at(slot);
          local.type = mode == ParameterMode::Mut ? views.second : views.first;
          int replacement = static_cast<int>(function.locals.size());
          function.locals.push_back({local.name, local.type, false, local.span,
                                     ParameterMode::Value, -1, 0});
          localRemap[slot] = replacement;
          projectedLocals[slot] = {
              {replacement, {Projection::dereference()}},
              checked.locals[slot].type != module.facts(p).type ? 1u : 0u};
        }
        for (const auto &child : p.children)
          aliases(child);
      };
      aliases(*source.parameters[i].pattern);
      patternBind(*source.parameters[i].pattern, place, mode);
    }
  const auto *value = &body;
  if (checked.defaultBorrowOperand[parameter]) {
    while (value->kind == Kind::Group)
      value = value->children[0].get();
    value = value->children[0].get();
  }
  auto result =
      checked.defaultBorrowed[parameter] &&
              module.facts(body).type != checked.defaultValueTypes[parameter]
          ? borrow(body, checked.locals[parameter].mode, false, true,
                   checked.defaultValueTypes[parameter])
          : expression(*value);
  if (live())
    returnValue(result, body.span);
  finishControlFlow();
  return std::move(function);
}

Builder::Value Builder::defaultArgument(
    std::size_t callee, std::size_t parameter, std::vector<Value> &arguments,
    std::vector<std::optional<Place>> &pending, DefaultFailurePaths &failures,
    Span span, const NodeFacts *call) {
  const auto &signature = module.function(callee);
  auto parameterType = [&](std::size_t index) {
    return call && !call->callParameterTypes.empty()
               ? call->callParameterTypes[index]
               : signature.locals[index].type;
  };
  auto errorType = call ? call->effect : signature.error;
  std::vector<Value> inputs;
  for (std::size_t i = 0; i < parameter; ++i) {
    if (arguments[i].access != ir::Access::Owned) {
      inputs.push_back(arguments[i]);
      continue;
    }
    if (!pending[i]) {
      auto owner = owners.find(arguments[i].id);
      pending[i] = owner == owners.end()
                       ? materialize(arguments[i], span, temporaryScope)
                       : owner->second;
    }
    inputs.push_back(
        emit({Op::BorrowRead, {}, {}, {}, "", *pending[i], -1, 0, span},
             parameterType(i), ir::Access::Read));
  }
  Instruction instruction{Op::Call,
                          {},
                          std::move(inputs),
                          {},
                          "",
                          {-1, {}},
                          defaultIndex(callee, parameter),
                          0,
                          span};
  if (call)
    instruction.typeArguments = call->typeArguments;
  auto resultType = call && !call->callDefaultAbiResults.empty()
                        ? call->callDefaultAbiResults[parameter]
                        : signature.defaultAbiResults[parameter];
  auto result = track(emit(std::move(instruction), resultType), span);
  if (errorType != Type::Unknown) {
    auto storage = materialize(result, span, temporaryScope);
    auto test = emit({Op::VariantTest, {}, {}, {}, "", storage, -1, 0, span},
                     Type::Bool);
    int success = block(), failure = block();
    terminate({Exit::Branch, test, success, failure});
    current = failure;
    auto failed = storage;
    failed.fields.push_back(Projection::field(2));
    auto error =
        track(emit({module.typeStore()->isCopy(errorType) ? Op::Load : Op::Move,
                    {},
                    {},
                    {},
                    "",
                    failed,
                    -1,
                    0,
                    span},
                   errorType),
              span);
    auto outcome = variant(failures.type, 1, {error}, span);
    failures.values.push_back(use(outcome));
    failures.blocks.push_back(current);
    jump(failures.done);
    current = success;
    auto passed = storage;
    passed.fields.push_back(Projection::field(1));
    auto type = call && !call->callDefaultValueTypes.empty()
                    ? call->callDefaultValueTypes[parameter]
                    : signature.defaultValueTypes[parameter];
    result = track(emit({module.typeStore()->isCopy(type) ? Op::Load : Op::Move,
                         {},
                         {},
                         {},
                         "",
                         passed,
                         -1,
                         0,
                         span},
                        type),
                   span);
  }
  auto expected = parameterType(parameter);
  if (signature.defaultBorrowOperand[parameter] &&
      module.typeStore()->isView(expected) &&
      module.typeStore()->view(expected).payload == result.type) {
    auto owner = owners.find(result.id);
    auto storage = owner == owners.end()
                       ? materialize(result, span, temporaryScope)
                       : owner->second;
    auto mode = module.typeStore()->view(expected).mode;
    result = emit({mode == ParameterMode::Read ? Op::ViewRead : Op::ViewMut,
                   {},
                   {},
                   {},
                   "",
                   storage,
                   -1,
                   0,
                   span},
                  expected);
  }
  auto mode = signature.locals[parameter].mode;
  if (mode == ParameterMode::Read || mode == ParameterMode::Mut) {
    auto owner = owners.find(result.id);
    auto storage = owner == owners.end()
                       ? materialize(result, span, temporaryScope)
                       : owner->second;
    if (signature.defaultBorrowed[parameter])
      storage.fields.push_back(Projection::dereference());
    return emit({mode == ParameterMode::Read ? Op::BorrowRead : Op::BorrowMut,
                 {},
                 {},
                 {},
                 "",
                 storage,
                 -1,
                 0,
                 span},
                expected,
                mode == ParameterMode::Read ? ir::Access::Read
                                            : ir::Access::Mut);
  }
  return result;
}
} // namespace mettle::lowering
