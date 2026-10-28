#pragma once

#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace mettle {
class TypeId {
public:
  constexpr TypeId() = default;
  constexpr std::uint32_t index() const { return value; }
  constexpr bool operator==(const TypeId &) const = default;
  static const TypeId Unknown, I32, Bool, Unit, Never;

private:
  friend class TypeStore;
  explicit constexpr TypeId(std::uint32_t index) : value(index) {}
  std::uint32_t value = 0;
};
inline constexpr TypeId TypeId::Unknown{0};
inline constexpr TypeId TypeId::I32{1};
inline constexpr TypeId TypeId::Bool{2};
inline constexpr TypeId TypeId::Unit{3};
inline constexpr TypeId TypeId::Never{4};
using Type = TypeId;
enum class ParameterMode { Value, Take, Read, Mut };

struct TypeField {
  std::string name;
  Type type;
};
struct ProductType {
  std::string name;
  std::vector<TypeField> fields;
  bool copyRequested;
  bool hasDestructor = false;
  int destructor = -1;
};
struct ViewType {
  Type payload;
  ParameterMode mode;
  std::string name;
};
class TypeStore {
public:
  Type declareProduct(std::string name, bool copyRequested);
  void defineProduct(Type type, std::vector<TypeField> fields);
  bool contains(Type type) const;
  bool isProduct(Type type) const;
  bool isView(Type type) const;
  Type viewType(Type payload, ParameterMode mode);
  const ViewType &view(Type type) const;
  void setDestructor(Type type, int function);
  bool needsDrop(Type type) const;
  bool containsViews(Type type) const;
  const ProductType &product(Type type) const;
  std::string_view name(Type type) const;
  bool isCopy(Type type) const;

private:
  struct Entry {
    bool view;
    std::size_t index;
  };
  std::vector<Entry> entries;
  std::vector<ProductType> products;
  std::vector<ViewType> views;
};
std::string_view typeName(Type type);
} // namespace mettle
