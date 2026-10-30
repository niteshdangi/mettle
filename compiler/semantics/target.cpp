#include "types/target.h"
#include "semantics/checker.h"

namespace mettle {
std::set<std::string> Checker::availableFeatures() const {
  auto features = guardedFeatures;
  if (current) {
    for (std::size_t index = 0; index < module.functions.size(); ++index)
      if (current == &module.functions[index])
        features.insert(checked.functions[index].targetFeatures.begin(),
                        checked.functions[index].targetFeatures.end());
  }
  return featureClosure(checked.targetDescription.arch, std::move(features));
}
void Checker::requireFeatures(const std::set<std::string> &features,
                              Span span) {
  if (!features.empty() && !featuresAvailable(checked.targetDescription,
                                              availableFeatures(), features))
    error("feature", span,
          "target operation/call requires established target feature "
          "availability");
}
void Checker::targetDeclarations() {
  for (auto &function : module.functions) {
    for (const auto &attribute : function.item.attributes) {
      if (attribute.name == "target_feature") {
        if (!checked.targetDescription.initialProfile())
          error("feature", attribute.span,
                "unsupported target feature profile");
        if (attribute.arguments.empty() || attribute.arguments.size() % 2 == 0)
          error("attribute", attribute.span,
                "target_feature requires a list of recognized feature strings");
        for (std::size_t i = 0; i < attribute.arguments.size(); ++i) {
          auto token = attribute.arguments[i];
          if (i % 2) {
            if (token.text != ",")
              error("attribute", token.span, "expected feature separator");
            continue;
          }
          auto name = token.text.size() >= 2
                          ? token.text.substr(1, token.text.size() - 2)
                          : "";
          if (token.kind != TokenKind::Text ||
              !recognizedFeature(checked.targetDescription.arch, name))
            error("feature", token.span,
                  "unknown target feature '" + name + "'");
          else if (!facts(function).targetFeatures.insert(name).second)
            error("attribute", token.span, "duplicate target feature");
        }
      } else if (attribute.name == "naked") {
        facts(function).naked = true;
        if (function.abi == "C-unwind")
          error("feature", attribute.span,
                "naked assembly has no supported unwind metadata form");
        if (attribute.parenthesized || function.abi.empty() ||
            function.foreignDeclaration || !function.unsafeFunction ||
            !function.genericParameters.empty() || function.variadic)
          error("attribute", attribute.span,
                "naked requires an unsafe non-generic physical ABI definition");
        for (const auto &parameter : function.parameters)
          if (parameter.defaultValue.get() || parameter.pattern)
            error("attribute", parameter.span,
                  "naked entries cannot have defaults or parameter patterns");
        const Node *body = function.body.get();
        if (body && body->kind == Kind::Block && body->children.size() == 1)
          body = body->children[0].get();
        if (!body || body->kind != Kind::Assembly ||
            body->assembly->variant != "naked_asm")
          error("attribute", function.span,
                "a naked function body must be exactly naked_asm");
      }
    }
    if (function.destructor && !facts(function).targetFeatures.empty() &&
        !featuresAvailable(checked.targetDescription, {},
                           facts(function).targetFeatures))
      error("feature", function.span,
            "implicit destructor dispatch cannot establish non-baseline target "
            "features");
  }
}
int Checker::featureTest(Node &node) {
  auto arch = node.name == "is_x86_feature_detected" ? TargetArch::X86_64
                                                     : TargetArch::Aarch64;
  if (!checked.targetDescription.initialProfile() ||
      arch != checked.targetDescription.arch ||
      !recognizedFeature(arch, node.text))
    error("feature", node.span,
          "unknown or unavailable target feature detector");
  else if (arch == TargetArch::Aarch64 &&
           !checked.targetDescription.baseline.contains(node.text))
    error("feature", node.span,
          "unsupported core feature detection: optional Darwin ARM64 features "
          "require a hosted detector");
  return inference.fresh(Type::Bool);
}
std::optional<int> Checker::targetCall(Node &call, bool reachable) {
  const auto &callee = *call.children[0];
  if (!callee.text.starts_with("core::arch::"))
    return std::nullopt;
  auto operation = targetOperation(callee.text);
  if (!operation) {
    error("feature", call.span,
          "unsupported architecture operation in the initial target inventory");
    return inference.fresh();
  }
  auto descriptor = *targetVector(operation->vector);
  bool unavailable = descriptor.arch != checked.targetDescription.arch ||
                     !checked.targetDescription.initialProfile();
  if (unavailable)
    error("feature", call.span,
          "architecture operation is unavailable on this target");
  requireUnsafe(call.span);
  if (!unavailable)
    requireFeatures({operation->feature}, call.span);
  auto vector =
      checked.types->vectorType(descriptor.name, descriptor.element,
                                descriptor.lanes, descriptor.alignment);
  using K = TargetOperation::Kind;
  if (call.children.size() != operation->arguments + 1 ||
      !callee.genericArguments.empty()) {
    error("type", call.span, "architecture operation argument count mismatch");
    return inference.fresh();
  }
  for (std::size_t i = 1; i < call.children.size(); ++i) {
    Type expected = vector;
    if (operation->kind == K::Splat || operation->kind == K::Set ||
        (operation->kind == K::Insert && i == 1))
      expected = operation->element;
    else if (operation->kind == K::Load ||
             (operation->kind == K::Store && i == 1)) {
      expected = checked.types->pointerType(
          descriptor.arch == TargetArch::X86_64 ? vector : operation->element,
          operation->kind == K::Store ? ParameterMode::Mut
                                      : ParameterMode::Read);
    } else if ((operation->kind == K::Extract && i == 2) ||
               (operation->kind == K::Insert && i == 3))
      expected = Type::I32;
    auto &argument = *call.children[i];
    contextualize(argument, expected);
    auto actual = node(argument, reachable);
    auto actualType = inference.value(actual);
    bool readablePointer =
        checked.types->isPointer(expected) &&
        checked.types->pointer(expected).mode == ParameterMode::Read &&
        checked.types->isPointer(actualType) &&
        checked.types->pointer(expected).payload ==
            checked.types->pointer(actualType).payload;
    if (!readablePointer)
      inference.equal(actual, inference.fresh(expected), argument.span, true);
    facts(call).machineBorrowModes.push_back(ParameterMode::Value);
    facts(call).callParameterTypes.push_back(expected);
    if ((operation->kind == K::Extract && i == 2) ||
        (operation->kind == K::Insert && i == 3)) {
      auto lane = constantInteger(argument);
      if (lane &&
          (*lane < 0 || static_cast<unsigned>(*lane) >= operation->lanes))
        error("type", argument.span,
              "vector lane is outside the target vector");
      else if (lane)
        facts(call).number = *lane;
    }
  }
  facts(call).machineOperation = callee.text;
  facts(call).machineType = vector;
  return inference.fresh(operation->kind == K::Store     ? Type::Unit
                         : operation->kind == K::Extract ? operation->element
                                                         : vector);
}
} // namespace mettle
