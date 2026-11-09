#include "types/type.h"

#include <algorithm>
#include <string>
#include <vector>

namespace mettle {
namespace {
// Builds an injective, compilation-independent encoding of a type. Every
// variable-length component is length-prefixed and every alternative carries
// its own tag, so distinct structures cannot produce the same text. Nominal
// types contribute their canonical package-qualified path; region identities
// are store-local, so regions are encoded by meaning: `static`, a position in
// an enclosing higher-ranked binder, or erased.
class IdentityEncoder {
public:
  explicit IdentityEncoder(const TypeStore &types) : types(types) {}

  std::string encode(Type type) {
    std::string out;
    write(out, type);
    return out;
  }

private:
  const TypeStore &types;
  // Innermost binder last; each entry lists the binder's region parameters.
  std::vector<std::vector<RegionId>> binders;
  std::vector<Type> active;

  static void text(std::string &out, std::string_view value) {
    out += std::to_string(value.size());
    out += ':';
    out += value;
  }
  static void number(std::string &out, std::uint64_t value) {
    out += std::to_string(value);
    out += ';';
  }
  static char mode(ParameterMode value) {
    switch (value) {
    case ParameterMode::Value:
      return 'v';
    case ParameterMode::Take:
      return 't';
    case ParameterMode::Read:
      return 'r';
    case ParameterMode::Mut:
      return 'm';
    }
    return '?';
  }

  void region(std::string &out, RegionId id) {
    if (id == RegionId::Static) {
      out += 's';
      return;
    }
    for (std::size_t depth = 0; depth < binders.size(); ++depth) {
      const auto &binder = binders[binders.size() - 1 - depth];
      auto found = std::find(binder.begin(), binder.end(), id);
      if (found != binder.end()) {
        out += 'b';
        number(out, depth);
        number(out, static_cast<std::uint64_t>(found - binder.begin()));
        return;
      }
    }
    // Free non-static regions do not take part in identity, as in Rust's
    // TypeId, where only bound (higher-ranked) regions are distinguished.
    out += 'e';
  }

  void regions(std::string &out, const std::vector<RegionId> &ids) {
    number(out, ids.size());
    for (auto id : ids)
      region(out, id);
  }

  void list(std::string &out, const std::vector<Type> &items) {
    number(out, items.size());
    for (auto item : items)
      write(out, item);
  }

  void literal(std::string &out, const NumericLiteral &value) {
    out += value.negative ? '-' : '+';
    number(out, value.magnitude[0]);
    number(out, value.magnitude[1]);
    text(out, value.floating);
    if (value.floatingBits) {
      out += 'f';
      number(out, *value.floatingBits);
    } else {
      out += 'n';
    }
  }

  void signature(std::string &out, const CallableType &callable) {
    binders.push_back(callable.regionParameters);
    regions(out, callable.regionParameters);
    out += mode(callable.mode);
    out += callable.unsafeCall ? 'u' : 's';
    out += callable.variadic ? 'V' : 'F';
    text(out, callable.abi);
    number(out, callable.parameters.size());
    for (const auto &parameter : callable.parameters) {
      out += mode(parameter.mode);
      write(out, parameter.type);
    }
    write(out, callable.result);
    write(out, callable.error);
    number(out, callable.targetFeatures.size());
    for (const auto &feature : callable.targetFeatures)
      text(out, feature);
    // The remaining fields of the store's signature identity
    // (sameSignature): spelled binder size (names are alpha-equivalent),
    // result sources and region relations.
    number(out, callable.regions.size());
    number(out, callable.resultSources.size());
    for (auto source : callable.resultSources)
      number(out, source);
    out += callable.resultFromEnvironment ? 'y' : 'n';
    regions(out, callable.parameterRegions);
    number(out, callable.regionRequirements.size());
    for (const auto &requirement : callable.regionRequirements) {
      region(out, requirement.longer);
      region(out, requirement.shorter);
    }
    binders.pop_back();
  }

  void write(std::string &out, Type type) {
    if (!types.contains(type) || type.index() < builtinTypeCount) {
      out += 'B';
      text(out, typeName(type));
      return;
    }
    if (std::find(active.begin(), active.end(), type) != active.end()) {
      // A type reached again through itself: its name closes the cycle.
      out += 'R';
      text(out, types.name(type));
      return;
    }
    active.push_back(type);
    struct Pop {
      std::vector<Type> &active;
      ~Pop() { active.pop_back(); }
    } pop{active};

    if (types.isPointer(type) || types.isView(type)) {
      const auto &view = types.view(type);
      out += types.isPointer(type) ? 'P' : 'W';
      out += mode(view.mode);
      if (types.isView(type))
        region(out, view.region);
      write(out, view.payload);
      return;
    }
    if (types.isSlice(type)) {
      const auto &slice = types.slice(type);
      out += 'L';
      number(out, static_cast<std::uint64_t>(slice.metadata));
      write(out, slice.element);
      return;
    }
    if (types.isErased(type)) {
      const auto &erased = types.erased(type);
      out += 'E';
      text(out, erased.name);
      binders.push_back(erased.regionParameters);
      regions(out, erased.regionParameters);
      list(out, erased.arguments);
      number(out, erased.associated.size());
      for (const auto &binding : erased.associated) {
        write(out, binding.parameter);
        write(out, binding.argument);
      }
      regions(out, erased.regionArguments);
      binders.pop_back();
      region(out, erased.bound);
      return;
    }
    if (types.isFunctionPointer(type)) {
      out += 'F';
      signature(out, types.callable(type));
      return;
    }
    if (types.isConstant(type)) {
      out += 'K';
      write(out, types.parameter(type).valueType);
      if (auto value = types.scalarConstantValue(type))
        literal(out, *value);
      else
        text(out, types.name(type));
      return;
    }
    if (types.isParameter(type)) {
      const auto &parameter = types.parameter(type);
      out += 'T';
      number(out, static_cast<std::uint64_t>(parameter.kind));
      text(out, parameter.name);
      text(out, parameter.operation);
      list(out, parameter.operands);
      return;
    }
    if (types.isProduct(type)) {
      const auto &record = types.product(type);
      out += 'N';
      number(out, static_cast<std::uint64_t>(record.kind));
      const auto origin =
          record.genericOrigin == Type::Unknown ? type : record.genericOrigin;
      text(out, types.product(origin).name);
      list(out, record.genericOrigin == Type::Unknown
                    ? record.genericParameters
                    : record.genericArguments);
      list(out, record.components);
      if (record.kind == AggregateKind::Array) {
        if (record.arrayCount == Type::Unknown) {
          out += 'c';
          number(out, record.fields.size());
        } else {
          write(out, record.arrayCount);
        }
      }
      regions(out, record.regionArguments);
      if (record.callable >= 0) {
        // Closures and generated futures are distinct per definition; their
        // name identifies the definition and their captures complete it.
        out += 'Q';
        signature(out, types.callable(type));
        number(out, record.fields.size());
        for (const auto &field : record.fields) {
          text(out, field.name);
          write(out, field.type);
        }
      }
      if (record.vector) {
        out += 'X';
        write(out, record.vector->element);
        number(out, record.vector->lanes);
      }
      return;
    }
    // Remaining store entries (opaque results) are nominal.
    out += 'O';
    text(out, types.name(type));
  }
};
} // namespace

std::string typeIdentity(const TypeStore &types, Type type) {
  return IdentityEncoder(types).encode(type);
}

bool containsFunctionPointer(const TypeStore &types, Type type) {
  std::vector<Type> active;
  auto visit = [&](auto &&self, Type nested) -> bool {
    if (!types.contains(nested) || nested.index() < builtinTypeCount)
      return false;
    if (types.isFunctionPointer(nested))
      return true;
    if (std::find(active.begin(), active.end(), nested) != active.end())
      return false;
    active.push_back(nested);
    bool found = false;
    auto any = [&](const std::vector<Type> &items) {
      for (auto item : items)
        found = found || self(self, item);
    };
    if (types.isPointer(nested) || types.isView(nested))
      found = self(self, types.view(nested).payload);
    else if (types.isSlice(nested))
      found = self(self, types.slice(nested).element);
    else if (types.isErased(nested)) {
      const auto &erased = types.erased(nested);
      any(erased.arguments);
      for (const auto &binding : erased.associated)
        found = found || self(self, binding.argument);
    } else if (types.isProduct(nested) && !types.isParameter(nested)) {
      const auto &record = types.product(nested);
      any(record.genericArguments);
      any(record.components);
      // Closure signatures and captures are part of the closure's identity.
      if (record.callable >= 0)
        for (const auto &field : record.fields)
          found = found || self(self, field.type);
    }
    active.pop_back();
    return found;
  };
  return visit(visit, type);
}
} // namespace mettle
