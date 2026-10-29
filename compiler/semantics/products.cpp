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
    checked.types->setProductLayout(identities.back(), productLayout(product));
  }
  for (std::size_t i = 0; i < module.products.size(); ++i) {
    const auto &product = module.products[i];
    auto savedEnvironment = genericEnvironment;
    genericEnvironment = &productGenerics.at(&product);
    std::unordered_set<std::string> names;
    std::vector<TypeField> fields;
    if (product.enumeration) {
      fields.push_back({"<tag>", Type::I32});
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
  std::function<void(std::size_t, unsigned)> visit = [&](std::size_t index,
                                                         unsigned depth) {
    if (depth > limits::typeDepth) {
      error("limit", module.products[index].span,
            "product nesting limit exceeded");
      return;
    }
    if (state[index] == 2)
      return;
    if (state[index] == 1) {
      error("type", module.products[index].span,
            "recursive by-value product has no finite layout");
      return;
    }
    state[index] = 1;
    const auto &type = checked.types->product(identities[index]);
    for (const auto &field : type.fields) {
      auto origin = checked.types->isProduct(field.type) &&
                            checked.types->product(field.type).genericOrigin !=
                                Type::Unknown
                        ? checked.types->product(field.type).genericOrigin
                        : field.type;
      auto found = std::find(identities.begin(), identities.end(), origin);
      if (found != identities.end())
        visit(static_cast<std::size_t>(found - identities.begin()), depth + 1);
      if (type.copyRequested && !checked.types->isCopy(field.type))
        error("type", module.products[index].span,
              "Copy product field '" + field.name + "' is not Copy");
    }
    state[index] = 2;
  };
  for (std::size_t i = 0; i < identities.size(); ++i)
    visit(i, 0);
  if (!diagnostics.empty())
    return;
}
} // namespace mettle
