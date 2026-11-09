#include "semantics/checker.h"
#include "support/limits.h"
#include "syntax/lexer.h"
#include "types/layout.h"
#include "types/machine.h"
#include <algorithm>
#include <functional>
#include <set>

namespace mettle {
void Checker::staticLocals() {
  if (facts(*current).naked)
    return;
  for (std::size_t i = 0; i < module.statics.size(); ++i) {
    if (checked.staticStorage[i].identity != i)
      continue;
    if (facts(*current).locals.size() >= limits::locals) {
      error("limit", current->span, "static storage root limit exceeded");
      return;
    }
    const auto &source = module.statics[i];
    auto type = checked.staticStorage[i].type;
    facts(*current).locals.push_back(
        {checked.staticStorage[i].name, type, source.mutableBinding,
         source.span, ParameterMode::Value, false, StorageDuration::Static,
         static_cast<int>(i)});
    localVariables[current].push_back(inference.fresh(type));
  }
}
std::optional<std::size_t> Checker::staticName(std::string_view name,
                                               Span span) {
  auto canonical =
      checked.symbols->lookup(checked.symbols->moduleOf(span), name,
                              resolution::Namespace::Value, span);
  if (!canonical)
    return std::nullopt;
  auto found = staticNames.find(*canonical);
  return found == staticNames.end() ? std::nullopt
                                    : std::optional(found->second);
}

// Raw pointers and a bare UnsafeCell are reachable only through unsafe code,
// which takes over the synchronization; every safe interior-mutable wrapper
// (Cell, RefCell, ...) still has to be Shareable.
bool Checker::shareable(Type type, Span span) {
  if (checked.types->isPointer(type))
    return true;
  if (checked.types->isProduct(type) &&
      checked.types->product(type).kind == AggregateKind::UnsafeCell)
    return true;
  interfaces::Solver solver(*checked.types, *checked.interfaceData, diagnostics,
                            interfaceAssumptions(), regionEnvironment());
  return solver.prove({type, Type::Unknown, interfaces::Property::Shareable},
                      span, false);
}

// Names and types first: associated-constant values and named enum
// discriminants read constant storage before the remaining static checks run.
void Checker::staticNamesAndTypes() {
  genericEnvironment = nullptr;
  checked.staticStorage.resize(module.statics.size());
  for (auto &source : module.statics)
    if (source.initializer.get())
      qualifyDottedPaths(*source.initializer);
  staticStates.resize(module.statics.size());
  for (std::size_t i = 0; i < module.statics.size(); ++i) {
    const auto &source = module.statics[i];
    auto &storage = checked.staticStorage[i];
    storage.identity = i;
    storage.name = definitionName(source.span, source.name);
    staticNames.emplace(storage.name, i);
  }
  inherentConstantNamesAndTypes();
  for (std::size_t i = 0; i < module.statics.size(); ++i) {
    const auto &source = module.statics[i];
    auto &storage = checked.staticStorage[i];
    storage.type = annotation(source.annotation, source.span);
  }
  staticsDeclared = true;
  // Resolve any values not forced by type annotations after storage types are
  // registered; this checks unused constants and catches forward-reference
  // cycles.
  for (std::size_t i = 0; i < inherentConstants.size(); ++i)
    (void)inherentConstantValue(i, inherentConstants[i].target);
}

void Checker::inherentConstantNamesAndTypes() {
  auto *saved = genericEnvironment;
  for (const auto &syntax : module.implementations) {
    if (!syntax.interface.empty() || syntax.negative ||
        std::none_of(syntax.associated.begin(), syntax.associated.end(),
                     [](const auto &item) { return item.constant; }))
      continue;

    auto environment =
        makeGenericEnvironment(syntax.genericParameters, syntax.constraints);
    environment.declarationSpan = syntax.span;
    genericEnvironment = &environment;
    pushRegionParameters(syntax.genericParameters, syntax.span);
    assumeRegionConstraints(syntax.constraints, syntax.span);
    auto target = annotation(syntax.target, syntax.span);
    environment.names["Self"] = target;
    auto [registered, inserted] =
        implementationGenerics.emplace(&syntax, std::move(environment));
    (void)inserted;
    genericEnvironment = &registered->second;

    // Scalar builtins own their constants by spelling, e.g. `char.MAX`.
    const bool scalarBuiltin = target != Type::Unknown &&
                               builtinType(syntax.target.name) == target &&
                               (isInteger(target) || isFloating(target) ||
                                target == Type::Char || target == Type::Bool);
    if (!scalarBuiltin &&
        (!checked.types->isProduct(target) ||
         (checked.types->product(target).kind != AggregateKind::Product &&
          checked.types->product(target).kind != AggregateKind::Enumeration))) {
      for (const auto &item : syntax.associated)
        if (item.constant)
          error("type", item.span,
                "inherent associated constants require a nominal type");
      popRegionParameters();
      genericEnvironment = saved;
      continue;
    }

    auto ownerType = target;
    if (!scalarBuiltin &&
        checked.types->product(ownerType).genericOrigin != Type::Unknown)
      ownerType = checked.types->product(ownerType).genericOrigin;
    const auto owner = scalarBuiltin ? syntax.target.name
                                     : checked.types->product(ownerType).name;
    for (const auto &item : syntax.associated) {
      if (!item.constant)
        continue;
      auto declaredType = annotation(item.annotation, item.span);
      if (declaredType == Type::Unknown)
        continue;
      if (!isInteger(declaredType) && declaredType != Type::Bool &&
          declaredType != Type::Char) {
        error("type", item.span,
              "associated constant requires a supported scalar type");
        continue;
      }
      if (!item.constantValue) {
        error("type", item.span, "associated constant requires a definition");
        continue;
      }
      auto index = inherentConstants.size();
      inherentConstants.push_back(
          {&syntax, &item, target, declaredType, Type::Unknown, 0});
      if (!inherentConstantNames.emplace(owner + "::" + item.name, index)
               .second)
        error("name", item.span, "duplicate associated constant");
    }
    popRegionParameters();
    genericEnvironment = saved;
  }
}

void Checker::staticDeclarations() {
  genericEnvironment = nullptr;
  for (std::size_t i = 0; i < module.statics.size(); ++i) {
    const auto &source = module.statics[i];
    auto &storage = checked.staticStorage[i];
    if (!checked.types->isSized(storage.type) ||
        checked.types->isSymbolic(storage.type) ||
        checked.types->uninhabited(storage.type))
      error("type", source.span,
            "static storage requires a concrete sized type");
    // Immutable statics are readable from every thread; mutable ones are only
    // reachable through unsafe code, which owns the synchronization.
    else if (!source.mutableBinding && !shareable(storage.type, source.span))
      error("type", source.span,
            "immutable static storage requires a Shareable type");
    storage.externalName = source.foreignDeclaration ? source.name : "";
    std::set<std::string> attributes;
    for (const auto &attribute : source.item.attributes) {
      if (!attributes.insert(attribute.name).second)
        error("attribute", attribute.span, "duplicate singleton attribute");
      if (attribute.name != "export_name" && attribute.name != "link_name" &&
          attribute.name != "link") {
        error("feature", attribute.span,
              "unsupported static storage attribute");
        continue;
      }
      if (attribute.arguments.size() != 1 ||
          attribute.arguments[0].kind != TokenKind::Text) {
        error("attribute", attribute.span,
              "linkage attributes require one constant text argument");
        continue;
      }
      const auto &text = attribute.arguments[0].text;
      auto name = text.substr(1, text.size() - 2);
      if (name.empty() || name.find('\\') != std::string::npos ||
          name.find('\0') != std::string::npos)
        error("attribute", attribute.span, "invalid linkage name");
      if (attribute.name == "link") {
        if (!source.foreignDeclaration ||
            name.find_first_not_of(
                "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
                "0123456789_+.-") != std::string::npos)
          error("attribute", attribute.span, "invalid import library name");
        storage.library = std::move(name);
      } else {
        if ((attribute.name == "link_name") != source.foreignDeclaration)
          error("attribute", attribute.span,
                "link_name is for imports; export_name is for definitions");
        storage.externalName = std::move(name);
      }
    }
  }
  std::map<std::string, std::size_t> identities;
  for (std::size_t i = 0; i < module.statics.size(); ++i) {
    const auto &storage = checked.staticStorage[i];
    if (storage.externalName.empty())
      continue;
    auto [found, inserted] = identities.emplace(storage.externalName, i);
    if (!inserted) {
      auto previous = found->second;
      if (checked.staticStorage[previous].type != storage.type ||
          module.statics[previous].mutableBinding !=
              module.statics[i].mutableBinding)
        error("signature", module.statics[i].span,
              "conflicting external static storage contract");
      if (!module.statics[i].foreignDeclaration)
        found->second = i;
    }
  }
  for (auto &storage : checked.staticStorage)
    if (!storage.externalName.empty())
      storage.identity = identities.at(storage.externalName);
}
void Checker::staticInitializers() {
  genericEnvironment = nullptr;
  unsafeDepth = 0;
  for (std::size_t i = 0; i < module.statics.size(); ++i)
    if (!module.statics[i].foreignDeclaration)
      staticValue(i);
}

std::optional<StaticConstant> Checker::staticValue(std::size_t index) {
  index = checked.staticStorage[index].identity;
  auto &storage = checked.staticStorage[index];
  if (staticStates[index] == 2)
    return storage.initializer;
  const auto &source = module.statics[index];
  if (source.foreignDeclaration) {
    error("constant", source.span,
          "required initialization cannot read mutable or foreign storage");
    return std::nullopt;
  }
  if (staticStates[index] == 1) {
    error("constant", source.span, "cycle in required static initialization");
    return std::nullopt;
  }
  staticStates[index] = 1;
  auto depth = unsafeDepth;
  unsafeDepth = 0;
  storage.initializer = staticInitializer(*source.initializer, storage.type);
  unsafeDepth = depth;
  staticStates[index] = 2;
  return storage.initializer;
}

std::optional<StaticConstant> Checker::staticInitializer(const Node &node,
                                                         Type type) {
  auto fail = [&](std::string message) -> std::optional<StaticConstant> {
    error("constant", node.span, std::move(message));
    return std::nullopt;
  };
  StaticConstant result;
  result.type = type;
  if (node.kind == Kind::Group)
    return staticInitializer(*node.children[0], type);
  if (node.kind == Kind::Unsafe) {
    auto depth = unsafeDepth;
    ++unsafeDepth;
    auto value = staticInitializer(*node.children[0], type);
    unsafeDepth = depth;
    return value;
  }
  if (node.kind == Kind::Block && node.children.size() == 1 &&
      !node.children[0]->semicolon)
    return staticInitializer(*node.children[0], type);
  const Node *literalNode = &node;
  bool negative = false;
  if (node.kind == Kind::Unary && node.text == "-") {
    literalNode = node.children[0].get();
    while (literalNode->kind == Kind::Group)
      literalNode = literalNode->children[0].get();
    negative = true;
  }
  if (literalNode->kind == Kind::Integer ||
      literalNode->kind == Kind::Floating) {
    auto suffix = literal(*literalNode, negative);
    if (suffix != Type::Unknown && suffix != type)
      return fail("static initializer literal suffix does not match its type");
    if ((literalNode->kind == Kind::Floating && !isFloating(type)) ||
        (literalNode->kind == Kind::Integer && !isInteger(type)))
      return fail("static initializer literal has an incompatible type");
    if (!facts(*literalNode).numeric)
      return std::nullopt;
    result.scalar = *facts(*literalNode).numeric;
    facts(*literalNode).type = type;
    if (isInteger(type) &&
        !integerLiteralFits(result.scalar, type, pointerBits()))
      return fail("static initializer integer is outside its type range");
    return result;
  }
  if (node.kind == Kind::Boolean && type == Type::Bool) {
    result.scalar.magnitude[0] = node.text == "true";
    return result;
  }
  if (constFunctionCall(node))
    return evaluatedStatic(node, type);
  if (isFloating(type) && needsEvaluator(node))
    return evaluatedStatic(node, type);
  if (node.kind == Kind::Character &&
      type == (node.flag ? Type::U8 : Type::Char)) {
    auto value = characterLiteral(node.text, node.flag, diagnostics, node.span);
    if (!value)
      return std::nullopt;
    result.scalar.magnitude[0] = *value;
    return result;
  }
  if (node.kind == Kind::Unit && type == Type::Unit)
    return result;
  if (node.kind == Kind::Text) {
    auto literal = textLiteralType(node);
    if (literal == Type::Unknown)
      return std::nullopt;
    // The literal's region is `static`; a static's annotation either names it
    // or leaves it unspecified.
    const bool staticView =
        checked.types->isView(type) &&
        checked.types->view(type).payload ==
            checked.types->view(literal).payload &&
        checked.types->view(type).mode == ParameterMode::Read &&
        (checked.types->view(type).region == RegionId::Static ||
         checked.types->view(type).region == RegionId::Unspecified);
    if (!staticView)
      if (!staticView)
        return fail("static initializer text literal has an incompatible type");
    result.kind = StaticConstant::Kind::Text;
    result.text = facts(node).text;
    return result;
  }
  if (checked.types->isSum(type) &&
      !(node.kind == Kind::Name && staticName(node.text, node.span))) {
    auto record = checked.types->product(type);
    const Node *callee =
        node.kind == Kind::Call ? node.children[0].get() : &node;
    int selected = -1;
    std::size_t first = node.kind == Kind::Call ? 1 : 0;
    if (node.kind == Kind::None && record.kind == AggregateKind::Optional)
      selected = 0;
    else if (node.kind == Kind::Variant &&
             record.kind == AggregateKind::Optional)
      selected = 1;
    else if (callee->kind == Kind::Name) {
      auto canonical = checked.symbols->lookup(
          checked.symbols->moduleOf(node.span), callee->text,
          resolution::Namespace::Value, node.span);
      auto origin = record.genericOrigin == Type::Unknown
                        ? record.name
                        : checked.types->product(record.genericOrigin).name;
      for (std::size_t i = 0; i < record.variants.size(); ++i)
        if ((canonical &&
             *canonical == origin + "::" + record.variants[i].name) ||
            (record.kind == AggregateKind::Ordering &&
             callee->text == origin + "::" + record.variants[i].name))
          selected = i;
    }
    if (selected < 0)
      return fail("required sum initialization requires a named variant");
    const auto &variant = record.variants[selected];
    if (node.children.size() != variant.fields.size() + first)
      return fail("constant variant initializer has the wrong payload count");
    result.kind = StaticConstant::Kind::Aggregate;
    result.selection = selected;
    if (record.layout.kind != LayoutKind::Transparent) {
      StaticConstant tag;
      tag.type = record.layout.tag;
      if (record.layout.discriminants.empty())
        tag.scalar.magnitude[0] = selected;
      else
        tag.scalar = record.layout.discriminants[selected];
      result.fields.push_back(std::move(tag));
    }
    for (std::size_t i = 0; i < variant.fields.size(); ++i) {
      auto value = staticInitializer(*node.children[first + i],
                                     record.fields[variant.fields[i]].type);
      if (!value)
        return std::nullopt;
      result.fields.push_back(std::move(*value));
    }
    return result;
  }
  if (node.kind == Kind::Name) {
    if (auto index = staticName(node.text, node.span)) {
      if (module.statics[*index].mutableBinding)
        return fail("required initialization cannot read mutable storage");
      if (checked.staticStorage[*index].type != type)
        return fail("static initializer storage type does not match");
      if (!checked.types->isCopy(type))
        return fail("required initialization cannot move from static storage");
      return staticValue(*index);
    }
    if (auto primitive = machineValue(node)) {
      if (inference.value(*primitive) != type)
        return fail("constant native value has an incompatible type");
      if (facts(node).numeric) {
        result.scalar = *facts(node).numeric;
        facts(node).type = type;
        return result;
      }
      if (checked.types->isProduct(type) &&
          checked.types->product(type).kind == AggregateKind::PhantomPinned) {
        result.kind = StaticConstant::Kind::Aggregate;
        return result;
      }
    }
    if (checked.types->isFunctionPointer(type)) {
      auto canonical = callableName(node.text, "", node.span);
      if (auto function = names.find(canonical); function != names.end()) {
        auto signature =
            checked.types->callableType(functionSignature(function->second));
        if (!compatibleCallable(checked.types->eraseRegions(signature),
                                checked.types->eraseRegions(type)))
          return fail(
              "constant function address has an incompatible signature");
        result.kind = StaticConstant::Kind::Function;
        result.symbol = function->second;
        return result;
      }
    }
    return fail("required initializer does not name constant storage");
  }
  if (node.kind == Kind::Field || node.kind == Kind::Index) {
    const Node *root = &node;
    std::vector<const Node *> projections;
    while (root->kind == Kind::Field || root->kind == Kind::Index ||
           root->kind == Kind::Group) {
      if (root->kind != Kind::Group)
        projections.push_back(root);
      root = root->children[0].get();
    }
    auto storage = root->kind == Kind::Name ? staticName(root->text, root->span)
                                            : std::nullopt;
    if (!storage || module.statics[*storage].mutableBinding)
      return fail("constant projection requires immutable static storage");
    auto value = staticValue(*storage);
    if (!value)
      return std::nullopt;
    for (auto projection = projections.rbegin();
         projection != projections.rend(); ++projection) {
      if (!checked.types->isProduct(value->type) ||
          checked.types->isSum(value->type))
        return fail("constant field projection requires a product");
      auto record = checked.types->product(value->type);
      if (checked.types->compactArray(value->type)) {
        error("feature", node.span,
              "constant projection of a large array is not implemented");
        return std::nullopt;
      }
      auto field = record.fields.size();
      if ((*projection)->kind == Kind::Index) {
        if (record.kind != AggregateKind::Array)
          return fail("constant indexing requires an array");
        auto index = constantInteger(*(*projection)->children[1]);
        if (index && *index >= 0)
          field = *index;
      } else
        for (std::size_t i = 0; i < record.fields.size(); ++i)
          if (record.fields[i].name == (*projection)->text)
            field = i;
      if (field >= record.fields.size())
        return fail("constant field or index is out of bounds");
      visibleField(value->type, field, node.span);
      if (record.layout.unionType)
        requireUnsafe(node.span);
      auto members = staticConstantFields(*checked.types, *value).value();
      auto selected =
          std::find_if(members.begin(), members.end(),
                       [&](const auto &entry) { return entry.first == field; });
      if (selected == members.end()) {
        error("feature", node.span,
              "constant union bit reinterpretation is not implemented");
        return std::nullopt;
      }
      auto next = value->fields[selected - members.begin()];
      value = std::move(next);
    }
    if (value->type != type)
      return fail("constant projection has an incompatible type");
    if (!checked.types->isCopy(type))
      return fail("required initialization cannot move from static storage");
    return value;
  }
  if (node.kind == Kind::Cast && checked.types->isPointer(type)) {
    auto target = annotation(node.annotation, node.span);
    if (target != type || node.children[0]->kind != Kind::Unary ||
        (node.children[0]->text != "read" && node.children[0]->text != "mut"))
      return fail("constant pointer conversion requires address provenance");
    auto source = checked.types->viewType(checked.types->pointer(type).payload,
                                          node.children[0]->text == "read"
                                              ? ParameterMode::Read
                                              : ParameterMode::Mut,
                                          RegionId::Static);
    if (!machineCastAllowed(*checked.types, source, type))
      return fail("invalid constant address conversion");
    auto value = staticInitializer(*node.children[0], source);
    if (value)
      value->type = type;
    return value;
  }
  const Node *addressPlace = nullptr;
  bool mutableAddress = false;
  if (node.kind == Kind::Unary && (node.text == "read" || node.text == "mut")) {
    addressPlace = node.children[0].get();
    mutableAddress = node.text == "mut";
  } else if (node.kind == Kind::Call && node.children.size() == 2 &&
             node.children[0]->kind == Kind::Name &&
             (node.children[0]->text == "core::ptr::from_ref" ||
              node.children[0]->text == "core::ptr::from_mut") &&
             checked.types->isPointer(type)) {
    addressPlace = node.children[1].get();
    mutableAddress = node.children[0]->text == "core::ptr::from_mut";
  }
  if (addressPlace &&
      (checked.types->isView(type) || checked.types->isPointer(type))) {
    const Node *place = addressPlace;
    std::vector<std::string> fields;
    while (place->kind == Kind::Field || place->kind == Kind::Group ||
           place->kind == Kind::Index) {
      if (place->kind == Kind::Field)
        fields.push_back(place->text);
      if (place->kind == Kind::Index) {
        auto index = constantInteger(*place->children[1]);
        if (!index || *index < 0)
          return fail("constant address index is out of bounds");
        fields.push_back(std::to_string(*index));
      }
      place = place->children[0].get();
    }
    if (place->kind != Kind::Name)
      return fail("constant address requires static storage provenance");
    auto index = staticName(place->text, place->span);
    if (!index)
      return fail("constant address requires static storage");
    auto payload = checked.staticStorage[*index].type;
    result.kind = StaticConstant::Kind::Address;
    result.symbol = checked.staticStorage[*index].identity;
    for (auto field = fields.rbegin(); field != fields.rend(); ++field) {
      if (!checked.types->isProduct(payload))
        return fail("constant address projection requires a product");
      const auto &record = checked.types->product(payload);
      auto found =
          std::find_if(record.fields.begin(), record.fields.end(),
                       [&](const auto &entry) { return entry.name == *field; });
      if (found == record.fields.end())
        return fail("unknown constant address projection");
      visibleField(payload, found - record.fields.begin(), node.span);
      result.projections.push_back(found - record.fields.begin());
      payload = found->type;
    }
    std::vector<Projection> projections;
    for (auto field : result.projections)
      projections.push_back(Projection::field(field));
    if (!alignedPlace(*checked.types, checked.staticStorage[*index].type,
                      projections))
      return fail("constant address cannot form an unaligned static reference");
    const auto &reference = checked.types->view(type);
    bool slice = checked.types->isSlice(reference.payload) &&
                 checked.types->isProduct(payload) &&
                 checked.types->product(payload).kind == AggregateKind::Array &&
                 checked.types->slice(reference.payload).element ==
                     checked.types->product(payload).components[0];
    if ((reference.payload != payload && !slice) ||
        mutableAddress != (reference.mode == ParameterMode::Mut))
      return fail("constant address type does not match its storage");
    if (slice)
      result.scalar.magnitude[0] = *checked.types->arrayLength(payload);
    if (mutableAddress && (!checked.types->isPointer(type) ||
                           !module.statics[*index].mutableBinding))
      return fail("mutable constant addresses require mutable raw storage");
    if (module.statics[*index].mutableBinding)
      requireUnsafe(node.span);
    if (module.statics[*index].mutableBinding && checked.types->isView(type))
      return fail("constant safe view cannot borrow mutable static storage");
    return result;
  }
  if (node.kind == Kind::Call && checked.types->isProduct(type) &&
      !checked.types->isSum(type)) {
    const auto &callee = *node.children[0];
    if (callee.kind != Kind::Name)
      return fail("required initialization cannot execute user functions");
    auto record = checked.types->product(type);
    auto separator = callee.text.rfind("::");
    auto owner = separator == std::string::npos
                     ? std::string{}
                     : callee.text.substr(0, separator);
    bool intrinsic =
        callee.text.ends_with("::new") &&
        ((record.kind == AggregateKind::Atomic &&
          owner.starts_with("core::sync::atomic::Atomic")) ||
         (record.kind == AggregateKind::UnsafeCell &&
          owner == "core::cell::UnsafeCell") ||
         (record.kind == AggregateKind::Cell && owner == "core::cell::Cell") ||
         (record.kind == AggregateKind::RefCell &&
          owner == "core::cell::RefCell") ||
         (record.kind == AggregateKind::ManualDrop &&
          owner == "core::mem::ManuallyDrop") ||
         (record.kind == AggregateKind::Uninit &&
          owner == "core::mem::MaybeUninit"));
    if (intrinsic) {
      auto arguments = callee.ownerGenericArguments.empty()
                           ? callee.genericArguments
                           : callee.ownerGenericArguments;
      if (record.kind == AggregateKind::Atomic || !arguments.empty()) {
        TypeSyntax syntax;
        syntax.name = owner;
        syntax.arguments = std::move(arguments);
        auto declared = machineAnnotation(syntax, callee.span, "");
        if (!declared || *declared != type)
          return fail("constant native constructor type does not match");
      }
      if (record.kind == AggregateKind::RefCell) {
        if (node.children.size() != 2)
          return fail("constant RefCell constructor requires one payload");
        auto payload =
            staticInitializer(*node.children[1], record.components[0]);
        if (!payload)
          return std::nullopt;
        StaticConstant counter;
        counter.type = Type::Isize;
        result.kind = StaticConstant::Kind::Aggregate;
        result.fields = {std::move(counter), std::move(*payload)};
        return result;
      }
    }
    auto canonical = typeName(callee.text, callee.span);
    auto origin = record.genericOrigin == Type::Unknown
                      ? record.name
                      : checked.types->product(record.genericOrigin).name;
    if (!intrinsic && canonical != origin)
      return fail("required initialization cannot execute user functions");
    if (!intrinsic && !callee.genericArguments.empty()) {
      TypeSyntax syntax;
      syntax.name = callee.text;
      syntax.arguments = callee.genericArguments;
      if (checked.types->eraseRegions(annotation(syntax, node.span)) !=
          checked.types->eraseRegions(type))
        return fail("constant product constructor type does not match");
    }
    if (!intrinsic)
      for (const auto &function : module.functions)
        if (function.constructor &&
            typeName(function.owner, function.span) == origin)
          return fail("const-function execution is not implemented");
    if (record.layout.unionType) {
      if (node.children.size() != 2 || node.children[1]->name.empty())
        return fail("constant union initialization selects one named field");
      const auto &child = *node.children[1];
      auto field = std::find_if(
          record.fields.begin(), record.fields.end(),
          [&](const auto &entry) { return entry.name == child.name; });
      if (field == record.fields.end())
        return fail("unknown constant union field");
      auto index = field - record.fields.begin();
      visibleField(type, index, child.span);
      auto value = staticInitializer(child, field->type);
      if (!value)
        return std::nullopt;
      result.kind = StaticConstant::Kind::Aggregate;
      result.selection = index;
      result.fields.push_back(std::move(*value));
      return result;
    }
    if (node.children.size() != record.fields.size() + 1)
      return fail("static product initializer has the wrong field count");
    result.kind = StaticConstant::Kind::Aggregate;
    result.fields.resize(record.fields.size());
    std::set<std::size_t> initialized;
    for (std::size_t i = 1; i < node.children.size(); ++i) {
      const auto &child = *node.children[i];
      std::size_t field = i - 1;
      if (!child.name.empty()) {
        auto found = std::find_if(
            record.fields.begin(), record.fields.end(),
            [&](const auto &entry) { return entry.name == child.name; });
        if (found == record.fields.end())
          return fail("unknown static initializer field");
        field = found - record.fields.begin();
      }
      if (!initialized.insert(field).second)
        return fail("duplicate static initializer field");
      if (!intrinsic)
        visibleField(type, field, child.span);
      auto value = staticInitializer(child, record.fields[field].type);
      if (!value)
        return std::nullopt;
      result.fields[field] = std::move(*value);
    }
    return result;
  }
  if ((node.kind == Kind::Tuple || node.kind == Kind::Array) &&
      checked.types->isProduct(type)) {
    auto record = checked.types->product(type);
    if ((node.kind == Kind::Tuple && record.kind != AggregateKind::Tuple) ||
        (node.kind == Kind::Array && record.kind != AggregateKind::Array))
      return fail("incompatible constant aggregate type");
    if (node.flag && node.kind == Kind::Array && node.children.size() == 2) {
      auto count = constantInteger(*node.children[1]);
      if (!count || *count < 0 ||
          static_cast<std::uint64_t>(*count) !=
              checked.types->arrayLength(type))
        return fail("constant aggregate length does not match");
      auto element = staticInitializer(*node.children[0], record.components[0]);
      if (!element)
        return std::nullopt;
      if (!*count && checked.types->needsDrop(element->type))
        return fail("constant repetition cannot execute an element destructor");
      if (*count > 1 && !checked.types->isCopy(element->type))
        return fail("constant array repetition requires Copy elements");
      if (checked.types->compactArray(type)) {
        result.kind = StaticConstant::Kind::Repeat;
        result.fields.push_back(std::move(*element));
        return result;
      }
      result.kind = StaticConstant::Kind::Aggregate;
      result.fields.assign(*count, *element);
      return result;
    }
    if (checked.types->compactArray(type)
            ? node.children.size() != checked.types->arrayLength(type)
            : node.children.size() != record.fields.size())
      return fail("constant aggregate length does not match");
    result.kind = StaticConstant::Kind::Aggregate;
    for (std::size_t i = 0; i < node.children.size(); ++i) {
      auto value = staticInitializer(*node.children[i],
                                     record.kind == AggregateKind::Array
                                         ? record.components[0]
                                         : record.fields[i].type);
      if (!value)
        return std::nullopt;
      result.fields.push_back(std::move(*value));
    }
    return result;
  }
  if ((node.kind == Kind::Binary || node.kind == Kind::Name ||
       (node.kind == Kind::Unary && (node.text == "-" || node.text == "!"))) &&
      isInteger(type)) {
    // The required-integer evaluator owns composition; scalar leaves retain
    // the same full-width carrier as runtime literals.
    auto identity = constantType(node, type);
    if (identity == Type::Unknown)
      return std::nullopt;
    auto value = checked.types->scalarConstantValue(identity);
    if (!value || checked.types->parameter(identity).valueType != type)
      return fail(
          "required static expression has an incompatible integer type");
    result.scalar = *value;
    if (!integerLiteralFits(result.scalar, type, pointerBits()))
      return fail("required static initializer overflows its type");
    return result;
  }
  bool scalar = isInteger(type) || type == Type::Bool || type == Type::Char;
  bool aggregate =
      checked.types->isProduct(type) && !checked.types->isSum(type) && !scalar;
  switch (node.kind) {
  case Kind::Cast:
  case Kind::If:
  case Kind::Match:
  case Kind::Block:
  case Kind::Index:
  case Kind::Field:
    if (scalar || aggregate)
      return evaluatedStatic(node, type);
    break;
  case Kind::Binary:
  case Kind::Name:
  case Kind::Unary:
    if ((scalar && !isInteger(type)) || aggregate)
      return evaluatedStatic(node, type);
    break;
  default:
    break;
  }
  return fail("static initializer requires a validated constant expression");
}
} // namespace mettle
