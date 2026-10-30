#include "semantics/checker.h"
#include "support/limits.h"
#include "types/layout.h"
#include <algorithm>
#include <bit>
#include <charconv>
#include <functional>
#include <set>
#include <tuple>

namespace mettle {
static bool literalDiscriminant(const Node &node) {
  const Node *value = &node;
  while (value->kind == Kind::Group)
    value = value->children[0].get();
  if (value->kind == Kind::Unary && value->text == "-")
    value = value->children[0].get();
  return value->kind == Kind::Integer;
}

ProductLayout Checker::productLayout(const Module::Product &product) {
  ProductLayout layout;
  layout.unionType = product.unionType;
  std::set<std::string> seen;
  for (const auto &attribute : product.item.attributes) {
    if (!seen.insert(attribute.name).second)
      error("attribute", attribute.span,
            "duplicate singleton attribute '" + attribute.name + "'");
    if (attribute.name == "layout") {
      bool c = false, integer = false, transparent = false;
      std::set<std::string> representations;
      if (attribute.arguments.empty() || attribute.arguments.size() % 2 == 0)
        error("attribute", attribute.span,
              "layout requires comma-separated representations");
      for (std::size_t i = 0; i < attribute.arguments.size(); ++i) {
        const auto &token = attribute.arguments[i];
        if (i % 2) {
          if (token.text != ",")
            error("attribute", token.span,
                  "expected a representation separator");
          continue;
        }
        if (!representations.insert(token.text).second)
          error("attribute", token.span, "duplicate layout representation");
        if (token.text == "C")
          c = true;
        else if (token.text == "transparent")
          transparent = true;
        else if (isInteger(builtinType(token.text))) {
          if (!product.enumeration)
            error("attribute", token.span,
                  "integer representation requires an enum");
          if (integer)
            error("attribute", token.span,
                  "an enum cannot have multiple integer representations");
          integer = true;
          layout.tag = builtinType(token.text);
        } else
          error("feature", token.span,
                "this layout representation is not implemented");
      }
      if (transparent && representations.size() != 1)
        error("attribute", attribute.span,
              "transparent layout cannot combine with another representation");
      layout.kind = transparent ? LayoutKind::Transparent
                    : c         ? LayoutKind::C
                    : integer   ? LayoutKind::Integer
                                : LayoutKind::Native;
    } else if (attribute.name == "align" || attribute.name == "packed") {
      std::uint64_t value =
          attribute.name == "packed" && !attribute.parenthesized ? 1 : 0;
      if (attribute.arguments.size() == 1) {
        auto spelling = attribute.arguments[0].text;
        spelling.erase(std::remove(spelling.begin(), spelling.end(), '_'),
                       spelling.end());
        int radix = 10;
        if (spelling.starts_with("0x") || spelling.starts_with("0o") ||
            spelling.starts_with("0b")) {
          radix = spelling[1] == 'x' ? 16 : spelling[1] == 'o' ? 8 : 2;
          spelling.erase(0, 2);
        }
        auto parsed = std::from_chars(
            spelling.data(), spelling.data() + spelling.size(), value, radix);
        if (parsed.ec != std::errc{} ||
            parsed.ptr != spelling.data() + spelling.size())
          value = 0;
      }
      if (!std::has_single_bit(value) || value > (std::uint64_t{1} << 29))
        error("attribute", attribute.span,
              "alignment must be a power of two in 1..2^29");
      if (attribute.name == "align")
        layout.alignment = value;
      else
        layout.packing = value;
    } else
      error("feature", attribute.span,
            "attribute '" + attribute.name + "' requires its implementation");
  }
  if (layout.alignment && layout.packing)
    error("attribute", product.span, "align and packed cannot be combined");
  if (layout.kind == LayoutKind::Transparent &&
      (layout.alignment || layout.packing))
    error("attribute", product.span,
          "transparent layout cannot be combined with align or packed");
  for (std::size_t field = 0; field < product.fields.size(); ++field) {
    for (const auto &attribute : product.fields[field].attributes) {
      if (attribute.name != "pinned")
        error("attribute", attribute.span,
              "this field attribute is not supported");
      else if (attribute.parenthesized)
        error("attribute", attribute.span,
              "pinned field attribute takes no arguments");
      else if (std::find(layout.pinnedFields.begin(), layout.pinnedFields.end(),
                         field) != layout.pinnedFields.end())
        error("attribute", attribute.span, "duplicate pinned field attribute");
      else
        layout.pinnedFields.push_back(static_cast<std::uint32_t>(field));
    }
  }
  if (product.enumeration && layout.kind == LayoutKind::Transparent &&
      product.variants.size() != 1)
    error("attribute", product.span,
          "transparent enum representation requires exactly one variant");
  if (product.enumeration && product.variants.empty() &&
      layout.kind != LayoutKind::Native)
    error("attribute", product.span,
          "an uninhabited enum cannot specify a tag representation");
  if (product.enumeration && layout.packing)
    error("attribute", product.span,
          "packed representation requires product or union storage");
  if (product.enumeration &&
      (layout.kind != LayoutKind::Native ||
       std::any_of(product.variants.begin(), product.variants.end(),
                   [](const auto &variant) {
                     return variant.discriminant != nullptr;
                   }))) {
    // A named discriminant reads constant storage, which is declared after
    // product layouts; its layout is recomputed once statics exist.
    if (!staticsDeclared &&
        std::any_of(product.variants.begin(), product.variants.end(),
                    [](const auto &variant) {
                      return variant.discriminant &&
                             !literalDiscriminant(*variant.discriminant);
                    })) {
      deferredLayouts.push_back(&product);
      return layout;
    }
    NumericLiteral next;
    bool overflow = false;
    std::set<std::tuple<bool, std::uint64_t, std::uint64_t>> used;
    for (const auto &variant : product.variants) {
      if (variant.discriminant) {
        const Node *value = variant.discriminant.get();
        while (value->kind == Kind::Group)
          value = value->children[0].get();
        bool negative = value->kind == Kind::Unary && value->text == "-";
        if (negative)
          value = value->children[0].get();
        if (value->kind == Kind::Integer) {
          auto suffix = literal(*value, negative);
          if (!facts(*value).numeric)
            return layout;
          if (suffix != Type::Unknown && suffix != layout.tag)
            error("type", value->span,
                  "discriminant suffix does not match the enum representation");
          next = *facts(*value).numeric;
          facts(*value).type = layout.tag;
        } else {
          auto identity = constantType(*variant.discriminant, layout.tag);
          if (identity != Type::Unknown) {
            if (checked.types->parameter(identity).valueType != layout.tag)
              error("type", variant.span,
                    "discriminant type does not match the enum representation");
            auto number = checked.types->scalarConstantValue(identity);
            if (number)
              next = *number;
            else
              error("type", variant.span,
                    "enum discriminant requires a concrete integer constant");
          }
        }
        overflow = false;
      }
      if (overflow || !integerLiteralFits(next, layout.tag, pointerBits()))
        error("type", variant.span,
              "enum discriminant is outside its representation");
      if (!next.magnitude[0] && !next.magnitude[1])
        next.negative = false;
      if (!used.emplace(next.negative, next.magnitude[0], next.magnitude[1])
               .second)
        error("type", variant.span, "duplicate enum discriminant");
      layout.discriminants.push_back(next);
      if (next.negative) {
        if (!next.magnitude[0]--)
          --next.magnitude[1];
        if (!next.magnitude[0] && !next.magnitude[1])
          next.negative = false;
      } else if (!++next.magnitude[0])
        overflow = !++next.magnitude[1];
    }
  }
  return layout;
}
void Checker::machineDeclarations() {
  for (const auto &declaration : module.products) {
    auto type =
        typeNames.at(definitionName(declaration.span, declaration.name));
    const auto &record = checked.types->product(type);
    if (record.layout.unionType) {
      if (record.fields.empty())
        error("type", declaration.span, "a union must have at least one field");
      for (const auto &field : record.fields)
        if (checked.types->needsDrop(field.type))
          error("type", declaration.span,
                "union fields requiring destruction must use ManuallyDrop "
                "storage");
      if (!record.layout.pinnedFields.empty())
        error("attribute", declaration.span,
              "union fields cannot be structurally pinned");
    }
    if (customRepresentation(*checked.types, type) &&
        !checked.types->isSymbolic(type) && !objectLayout(*checked.types, type))
      error("attribute", declaration.span,
            "object layout cannot be established for this representation");
    if (record.layout.packing) {
      std::set<Type> visited;
      std::function<bool(Type)> raised = [&](Type nested) {
        if (!checked.types->isProduct(nested) || !visited.insert(nested).second)
          return false;
        const auto &product = checked.types->product(nested);
        if (product.layout.alignment)
          return true;
        for (const auto &field : product.fields)
          if (raised(field.type))
            return true;
        return false;
      };
      for (const auto &field : record.fields) {
        if (raised(field.type))
          error("attribute", declaration.span,
                "packed storage cannot contain explicitly aligned storage "
                "without indirection");
        auto index = static_cast<std::uint32_t>(&field - record.fields.data());
        if (std::find(record.layout.pinnedFields.begin(),
                      record.layout.pinnedFields.end(),
                      index) != record.layout.pinnedFields.end() &&
            objectLayout(*checked.types, field.type) &&
            objectLayout(*checked.types, field.type)->alignment >
                record.layout.packing)
          error("attribute", declaration.span,
                "an unaligned packed field cannot be structurally pinned");
      }
    }
  }
  std::set<Type> validatedLayouts;
  auto validateLayout = [&](Type type, Span span) {
    if (!checked.types->isProduct(type) ||
        !validatedLayouts.insert(type).second ||
        checked.types->isSymbolic(type) || !checked.types->isSized(type))
      return;
    auto layout = objectLayout(*checked.types, type);
    if (!layout)
      error(
          checked.types->product(type).kind == AggregateKind::Array
              ? "limit"
              : "attribute",
          span,
          checked.types->product(type).kind == AggregateKind::Array
              ? "array size exceeds target address space"
              : "object layout cannot be established for this representation");
    else if (layout->size > limits::objectBytes)
      error("limit", span, "array size exceeds target address space");
  };
  for (const auto &[syntax, resolved] : checked.nodes) {
    validateLayout(resolved.type, syntax->span);
    validateLayout(resolved.machineType, syntax->span);
    for (auto type : resolved.typeArguments)
      validateLayout(type, syntax->span);
  }
  for (std::size_t i = 0; i < module.functions.size(); ++i) {
    validateLayout(checked.functions[i].result, module.functions[i].span);
    for (const auto &local : checked.functions[i].locals)
      validateLayout(local.type, local.span);
  }
  for (std::size_t i = 0; i < checked.staticStorage.size(); ++i)
    validateLayout(checked.staticStorage[i].type, module.statics[i].span);
  auto floatingPolicy = [&](const Attribute &attribute,
                            FloatingPolicy &policy) {
    std::set<std::string> seen;
    if (attribute.arguments.empty() || attribute.arguments.size() % 2 == 0)
      error("attribute", attribute.span,
            "fast_math requires a comma-separated list of relaxations");
    for (std::size_t i = 0; i < attribute.arguments.size(); ++i) {
      const auto &token = attribute.arguments[i];
      if (i % 2) {
        if (token.text != ",")
          error("attribute", token.span,
                "expected ',' between floating relaxations");
        continue;
      }
      if (!seen.insert(token.text).second)
        error("attribute", token.span, "duplicate floating relaxation");
      if (token.text == "reassociate")
        policy.reassociate = true;
      else if (token.text == "contract")
        policy.contract = true;
      else if (token.text == "no_nans")
        policy.noNaNs = true;
      else if (token.text == "no_infinities")
        policy.noInfinities = true;
      else if (token.text == "no_signed_zeros")
        policy.noSignedZeros = true;
      else if (token.text == "reciprocal")
        policy.reciprocal = true;
      else if (token.text == "approximate_functions")
        policy.approximateFunctions = true;
      else
        error("attribute", token.span,
              "unknown floating relaxation '" + token.text + "'");
    }
  };
  std::vector<std::pair<std::vector<std::string>, FloatingPolicy>>
      modulePolicies;
  for (const auto &declaration : module.modules) {
    FloatingPolicy policy;
    std::set<std::string> seen;
    for (const auto &attribute : declaration.item.attributes) {
      if (!seen.insert(attribute.name).second)
        error("attribute", attribute.span,
              "duplicate singleton module attribute");
      if (attribute.name == "fast_math")
        floatingPolicy(attribute, policy);
      else
        error("feature", attribute.span,
              "unsupported module attribute '" + attribute.name + "'");
    }
    auto scope = declaration.item.scope;
    scope.push_back(declaration.name);
    modulePolicies.emplace_back(std::move(scope), policy);
  }
  auto mergePolicy = [](FloatingPolicy &target, const FloatingPolicy &source) {
    target.reassociate |= source.reassociate;
    target.contract |= source.contract;
    target.noNaNs |= source.noNaNs;
    target.noInfinities |= source.noInfinities;
    target.noSignedZeros |= source.noSignedZeros;
    target.reciprocal |= source.reciprocal;
    target.approximateFunctions |= source.approximateFunctions;
  };
  std::map<std::string, std::pair<Type, bool>> symbols;
  std::set<std::string> functionSymbols;
  for (auto &function : module.functions) {
    for (const auto &[scope, policy] : modulePolicies)
      if (function.item.scope.size() >= scope.size() &&
          std::equal(scope.begin(), scope.end(), function.item.scope.begin()))
        mergePolicy(facts(function).floatingPolicy, policy);
    if (facts(function).naked) {
      if (checked.types->needsDrop(facts(function).result))
        error("attribute", function.span,
              "naked physical entries cannot return managed owners");
      for (std::size_t p = 0;
           p < function.parameters.size() && p < facts(function).locals.size();
           ++p) {
        const auto &parameter = facts(function).locals[p];
        if ((parameter.mode == ParameterMode::Take ||
             parameter.mode == ParameterMode::Value) &&
            checked.types->needsDrop(parameter.type))
          error("attribute", function.parameters[p].span,
                "naked physical entries cannot own values requiring cleanup");
      }
    }
    auto signatureFeature = [&](Type type) {
      if (auto descriptor = targetVector(checked.types->name(type));
          descriptor && !featuresAvailable(checked.targetDescription,
                                           facts(function).targetFeatures,
                                           {descriptor->feature}))
        error(
            "feature", function.span,
            "native vector physical ABI requires its declared target feature");
    };
    signatureFeature(facts(function).result);
    for (std::size_t p = 0;
         p < function.parameters.size() && p < facts(function).locals.size();
         ++p)
      if (facts(function).locals[p].mode == ParameterMode::Value ||
          facts(function).locals[p].mode == ParameterMode::Take)
        signatureFeature(facts(function).locals[p].type);
    auto abi = function.abi;
    if (!abi.empty() && abi != "C" && abi != "C-unwind" && abi != "system")
      error("feature", function.span, "unsupported foreign ABI '" + abi + "'");
    if (function.variadic && abi.empty())
      error("signature", function.span,
            "variadic functions require a foreign ABI");
    if (!abi.empty() && !facts(function).genericParameters.empty())
      error("signature", function.span,
            "foreign functions cannot have generic type or const parameters");
    std::set<std::string> attributes;
    auto symbol = function.abi.empty() ? std::string{} : function.name;
    for (const auto &attribute : function.item.attributes) {
      if (!attributes.insert(attribute.name).second)
        error("attribute", attribute.span,
              "duplicate singleton attribute '" + attribute.name + "'");
      if (attribute.name == "fast_math")
        floatingPolicy(attribute, facts(function).floatingPolicy);
      else if (attribute.name == "export_name" ||
               attribute.name == "link_name") {
        if (attribute.arguments.size() != 1 ||
            attribute.arguments[0].kind != TokenKind::Text) {
          error("attribute", attribute.span,
                "symbol attributes require one constant text argument");
          continue;
        }
        auto text = attribute.arguments[0].text;
        symbol = text.substr(1, text.size() - 2);
        if (symbol.empty() || symbol.find('\\') != std::string::npos ||
            symbol.find('\0') != std::string::npos)
          error("attribute", attribute.span, "invalid external symbol name");
        if ((attribute.name == "link_name") != function.foreignDeclaration)
          error("attribute", attribute.span,
                "link_name is for imports; export_name is for definitions");
      } else if (attribute.name == "link") {
        if (!function.foreignDeclaration || attribute.arguments.size() != 1 ||
            attribute.arguments[0].kind != TokenKind::Text) {
          error("attribute", attribute.span,
                "link requires an imported declaration and one constant text");
          continue;
        }
        auto text = attribute.arguments[0].text;
        auto library = text.substr(1, text.size() - 2);
        if (library.empty() ||
            library.find_first_not_of(
                "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
                "0123456789_+.-") != std::string::npos)
          error("attribute", attribute.span, "invalid import library name");
        facts(function).library = std::move(library);
      } else if (attribute.name == "target_feature" ||
                 attribute.name == "naked") {
        // Checked before bodies, so call-site feature checks are
        // order-independent.
      } else
        error("feature", attribute.span,
              "attribute '" + attribute.name +
                  "' requires its machine implementation");
    }
    if (!function.abi.empty() && facts(function).error != Type::Unknown)
      error("signature", function.span,
            "foreign ABI cannot carry a native typed failure");
    if (symbol.empty())
      continue;
    functionSymbols.insert(symbol);
    if (requireEntry && symbol == "main" && function.name != "main")
      error("signature", function.span,
            "external main symbol conflicts with the hosted entry point");
    if (!function.abi.empty()) {
      std::set<Type> active;
      std::function<bool(Type)> compatible = [&](Type type) {
        if (type == Type::Unit || type == Type::Never || isNumeric(type) ||
            type == Type::Bool || type == Type::Char)
          return true;
        if (nativeVector(*checked.types, type))
          return true;
        if (checked.types->isPointer(type) || checked.types->isView(type))
          return checked.types->pointerMetadata(
                     checked.types->view(type).payload) ==
                 PointerMetadata::None;
        if (checked.types->isFunctionPointer(type))
          return !checked.types->callable(type).abi.empty();
        if (!checked.types->isProduct(type) || !active.insert(type).second)
          return false;
        const auto &record = checked.types->product(type);
        bool result = record.layout.kind != LayoutKind::Native ||
                      record.kind == AggregateKind::Array;
        for (const auto &field : record.fields)
          result &= compatible(field.type);
        active.erase(type);
        return result;
      };
      if (!compatible(facts(function).result))
        error("feature", function.span,
              "foreign result has no specified C-compatible representation");
      for (std::size_t p = 0;
           p < function.parameters.size() && p < facts(function).locals.size();
           ++p) {
        const auto &parameter = facts(function).locals[p];
        if ((parameter.mode == ParameterMode::Read ||
             parameter.mode == ParameterMode::Mut)
                ? !checked.types->isSized(parameter.type)
                : !compatible(parameter.type))
          error(
              "feature", function.parameters[p].span,
              "foreign parameter has no specified C-compatible representation");
      }
    }
    auto signature = checked.types->callableType(functionSignature(
        static_cast<std::size_t>(&function - module.functions.data())));
    if (auto found = symbols.find(symbol); found != symbols.end()) {
      if (found->second.first != signature ||
          (found->second.second && function.body.get()))
        error("signature", function.span,
              "conflicting external symbol '" + symbol + "'");
      found->second.second |= function.body.get() != nullptr;
    } else
      symbols.emplace(symbol,
                      std::pair{signature, function.body.get() != nullptr});
    facts(function).externalName = std::move(symbol);
  }
  for (auto &closure : checked.closureBodies)
    closure->function.floatingPolicy = facts(*closure->parent).floatingPolicy;
  for (std::size_t i = 0; i < module.statics.size(); ++i) {
    const auto &storage = checked.staticStorage[i];
    if (storage.externalName.empty())
      continue;
    if (functionSymbols.contains(storage.externalName)) {
      error("signature", module.statics[i].span,
            "conflicting external function and storage symbol '" +
                storage.externalName + "'");
      continue;
    }
    if (requireEntry && storage.externalName == "main")
      error("signature", module.statics[i].span,
            "static symbol conflicts with the hosted entry point");
    bool definition = !module.statics[i].foreignDeclaration;
    auto [found, inserted] = symbols.emplace(
        storage.externalName, std::pair{storage.type, definition});
    if (!inserted) {
      if (found->second.first != storage.type ||
          (found->second.second && definition))
        error("signature", module.statics[i].span,
              "conflicting external symbol '" + storage.externalName + "'");
      found->second.second |= definition;
    }
  }
}
} // namespace mettle
