#include "semantics/checker.h"
#include "support/limits.h"
#include <algorithm>
#include <functional>
#include <unordered_set>

namespace mettle {
void Checker::products() {
  std::vector<Type> identities;
  for (const auto &product : module.products) {
    identities.push_back(
        typeNames.at(definitionName(product.span, product.name)));
    if (!imported(product.span))
      checked.types->setProductLayout(identities.back(),
                                      productLayout(product));
  }
  std::vector<std::vector<Span>> fieldSpans(module.products.size());
  for (std::size_t i = 0; i < module.products.size(); ++i) {
    const auto &product = module.products[i];
    if (imported(product.span))
      continue;
    auto savedEnvironment = genericEnvironment;
    genericEnvironment = &productGenerics.at(&product);
    std::unordered_set<std::string> names;
    std::vector<TypeField> fields;
    if (product.enumeration) {
      fields.push_back({"<tag>", Type::I32});
      fieldSpans[i].push_back(product.span);
      std::vector<VariantType> variants;
      for (const auto &variant : product.variants) {
        if (!names.insert(variant.name).second)
          error("name", variant.span,
                "duplicate variant '" + variant.name + "'");
        VariantType checkedVariant{variant.name, {}};
        std::unordered_set<std::string> fieldNames;
        for (const auto &field : variant.fields) {
          if (!fieldNames.insert(field.name).second)
            error("name", field.span,
                  "duplicate variant field '" + field.name + "'");
          checkedVariant.fields.push_back(
              static_cast<std::uint32_t>(fields.size()));
          fields.push_back({field.name, annotation(field.annotation, field.span,
                                                   product.name)});
          fieldSpans[i].push_back(field.span);
        }
        variants.push_back(std::move(checkedVariant));
      }
      checked.types->defineEnumeration(identities[i], std::move(variants),
                                       std::move(fields));
      genericEnvironment = savedEnvironment;
      continue;
    }
    for (const auto &field : product.fields) {
      if (!names.insert(field.name).second)
        error("name", field.span, "duplicate field '" + field.name + "'");
      fields.push_back(
          {field.name, annotation(field.annotation, field.span, product.name)});
      fieldSpans[i].push_back(field.span);
    }
    checked.types->defineProduct(identities[i], std::move(fields));
    if (product.hasDestructor) {
      checked.types->setDestructor(identities[i], -1);
      if (product.copyRequested)
        error("type", product.span, "a type with a destructor cannot be Copy");
    }
    genericEnvironment = savedEnvironment;
  }
  if (!diagnostics.empty())
    return;
  checked.types->refreshProductInstances();
  std::vector<int> state(module.products.size());
  std::function<void(std::size_t, unsigned, Span)> visit;
  std::set<Type> structural;
  std::function<void(Type, unsigned, Span)> member = [&](Type type,
                                                         unsigned depth,
                                                         Span span) {
    if (!checked.types->isProduct(type))
      return;
    if (depth > limits::typeDepth) {
      error("limit", span, "product nesting limit exceeded");
      return;
    }
    const auto &record = checked.types->product(type);
    auto origin =
        record.genericOrigin == Type::Unknown ? type : record.genericOrigin;
    auto found = std::find(identities.begin(), identities.end(), origin);
    if (found != identities.end()) {
      visit(static_cast<std::size_t>(found - identities.begin()), depth, span);
      return;
    }
    if (!structural.insert(type).second) {
      error("type", span, "recursive by-value product has no finite layout");
      return;
    }
    if (record.kind == AggregateKind::Array && !record.components.empty())
      member(record.components[0], depth + 1, span);
    else
      for (const auto &field : record.fields)
        member(field.type, depth + 1, span);
    structural.erase(type);
  };
  visit = [&](std::size_t index, unsigned depth, Span use) {
    if (imported(module.products[index].span))
      return;
    if (depth > limits::typeDepth) {
      error("limit", module.products[index].span,
            "product nesting limit exceeded");
      return;
    }
    if (state[index] == 2)
      return;
    if (state[index] == 1) {
      error("type", use, "recursive by-value product has no finite layout");
      return;
    }
    state[index] = 1;
    // Substitution interns types, so keep copies of the product's parts.
    const auto type = checked.types->product(identities[index]);
    // A Copy product whose fields are Copy only when its unbounded type
    // parameters are is Copy exactly when its type arguments are.
    std::vector<TypeBinding> assumeCopy;
    for (auto parameter : type.genericParameters)
      if (checked.types->isParameter(parameter) &&
          !checked.types->parameter(parameter).copyRequested)
        assumeCopy.push_back({parameter, Type::I32});
    bool conditional = false;
    for (std::size_t f = 0; f < type.fields.size(); ++f) {
      const auto &field = type.fields[f];
      member(field.type, depth + 1, fieldSpans[index][f]);
      if (!type.copyRequested || checked.types->isCopy(field.type))
        continue;
      if (!assumeCopy.empty() &&
          checked.types->isCopy(
              checked.types->substitute(field.type, assumeCopy))) {
        conditional = true;
        continue;
      }
      error("type", module.products[index].span,
            "Copy product field '" + field.name + "' is not Copy");
    }
    if (conditional)
      checked.types->setConditionalCopy(identities[index]);
    state[index] = 2;
  };
  for (std::size_t i = 0; i < identities.size(); ++i)
    visit(i, 0, module.products[i].span);
  if (!diagnostics.empty())
    return;
}
} // namespace mettle
