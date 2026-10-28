#include "semantics/checker.h"
#include "support/limits.h"
#include <algorithm>
#include <functional>
#include <unordered_set>

namespace mettle {
void Checker::products() {
  std::vector<Type> identities;
  for (const auto &product : module.products) {
    if (typeNames.contains(product.name)) {
      error("name", product.span, "duplicate type '" + product.name + "'");
      identities.push_back(Type::Unknown);
    } else {
      auto identity =
          checked.types->declareProduct(product.name, product.copyRequested);
      identities.push_back(identity);
      typeNames.emplace(product.name, identity);
    }
  }
  if (!diagnostics.empty())
    return;
  for (std::size_t i = 0; i < module.products.size(); ++i) {
    const auto &product = module.products[i];
    std::unordered_set<std::string> names;
    std::vector<TypeField> fields;
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
    for (const auto &field : product.fields)
      if (!field.annotation.view.empty()) {
        if (field.annotation.sources.empty())
          error("type", field.span,
                "stored view field requires a declared region source");
        for (const auto &source : field.annotation.sources)
          if (std::find(product.regions.begin(), product.regions.end(),
                        source) == product.regions.end())
            error("name", field.span,
                  "unknown stored-view region '" + source + "'");
      }
  }
  if (!diagnostics.empty())
    return;
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
      auto found = std::find(identities.begin(), identities.end(), field.type);
      if (found != identities.end())
        visit(static_cast<std::size_t>(found - identities.begin()), depth + 1);
      if (field.type == Type::Never)
        error("feature", module.products[index].span,
              "uninhabited fields are not implemented yet");
      else if (type.copyRequested && !checked.types->isCopy(field.type))
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
