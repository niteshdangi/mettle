#pragma once

#include <compare>
#include <initializer_list>
#include <iterator>
#include <memory>
#include <stdexcept>
#include <unordered_map>
#include <utility>
#include <vector>

namespace mettle {
// Only checked imports share storage; source syntax stays uniquely owned.
template <class T> class Declarations {
  using Storage = std::vector<std::shared_ptr<T>>;

public:
  using value_type = T;
  class Iterator {
  public:
    using iterator_category = std::random_access_iterator_tag;
    using value_type = T;
    using difference_type = std::ptrdiff_t;
    using reference = const T &;
    using pointer = const T *;
    Iterator() = default;
    reference operator*() const { return **position; }
    pointer operator->() const { return &**this; }
    reference operator[](difference_type offset) const {
      return *position[offset];
    }
    Iterator &operator++() {
      ++position;
      return *this;
    }
    Iterator operator++(int) {
      auto old = *this;
      ++*this;
      return old;
    }
    Iterator &operator--() {
      --position;
      return *this;
    }
    Iterator operator--(int) {
      auto old = *this;
      --*this;
      return old;
    }
    Iterator &operator+=(difference_type offset) {
      position += offset;
      return *this;
    }
    Iterator &operator-=(difference_type offset) {
      position -= offset;
      return *this;
    }
    friend Iterator operator+(Iterator it, difference_type offset) {
      return it += offset;
    }
    friend Iterator operator+(difference_type offset, Iterator it) {
      return it += offset;
    }
    friend Iterator operator-(Iterator it, difference_type offset) {
      return it -= offset;
    }
    friend difference_type operator-(Iterator left, Iterator right) {
      return left.position - right.position;
    }
    auto operator<=>(const Iterator &) const = default;

  private:
    friend class Declarations;
    explicit Iterator(typename Storage::const_iterator position)
        : position(position) {}
    typename Storage::const_iterator position;
  };
  class Local {
  public:
    class Iterator {
    public:
      T &operator*() const { return owner.edit(index); }
      Iterator &operator++() {
        ++index;
        skip();
        return *this;
      }
      bool operator!=(const Iterator &other) const {
        return index != other.index;
      }

    private:
      friend class Local;
      Iterator(Declarations &owner, std::size_t index)
          : owner(owner), index(index) {
        skip();
      }
      void skip() {
        while (index < owner.size() && owner[index].item.checkedImport)
          ++index;
      }
      Declarations &owner;
      std::size_t index;
    };
    Iterator begin() { return {owner, 0}; }
    Iterator end() { return {owner, owner.size()}; }

  private:
    friend class Declarations;
    explicit Local(Declarations &owner) : owner(owner) {}
    Declarations &owner;
  };
  Declarations() = default;
  Declarations(std::initializer_list<T> values) {
    reserve(values.size());
    for (const auto &value : values)
      push_back(value);
  }
  Declarations(const Declarations &other) {
    values.reserve(other.size());
    for (const auto &value : other.values)
      values.push_back(value->item.checkedImport ? value
                                                 : std::make_shared<T>(*value));
  }
  Declarations &operator=(const Declarations &other) {
    if (this != &other) {
      *this = Declarations(other);
    }
    return *this;
  }
  Declarations(Declarations &&) noexcept = default;
  Declarations &operator=(Declarations &&) noexcept = default;
  Iterator begin() const { return Iterator(values.begin()); }
  Iterator end() const { return Iterator(values.end()); }
  Local local() { return Local(*this); }
  std::size_t size() const { return values.size(); }
  bool empty() const { return values.empty(); }
  const T &operator[](std::size_t index) const { return *values[index]; }
  const T &at(std::size_t index) const { return *values.at(index); }
  const T &front() const { return *values.front(); }
  const T &back() const { return *values.back(); }
  std::shared_ptr<const T> shared(std::size_t index) const {
    return values.at(index);
  }
  T &edit(std::size_t index) {
    auto &value = values.at(index);
    if (!value.unique()) {
      auto copy = std::make_shared<T>(*value);
      positions.reset();
      value = std::move(copy);
    }
    return *value;
  }
  std::size_t indexOf(const T *value) const {
    if (!positions) {
      auto indexed = std::make_unique<Positions>();
      indexed->reserve(values.size());
      for (std::size_t i = 0; i < values.size(); ++i)
        indexed->emplace(values[i].get(), i);
      positions = std::move(indexed);
    }
    auto found = positions->find(value);
    if (found == positions->end())
      throw std::out_of_range("declaration does not belong to this module");
    return found->second;
  }
  void reserve(std::size_t count) { values.reserve(count); }
  void push_back(T value) {
    auto record = std::make_shared<T>(std::move(value));
    positions.reset();
    values.push_back(std::move(record));
  }
  void resize(std::size_t count) {
    if (count < size()) {
      values.resize(count);
      positions.reset();
    } else
      while (size() < count)
        push_back(T{});
  }
  void clear() {
    values.clear();
    positions.reset();
  }
  void append(Declarations other) {
    values.insert(values.end(), std::make_move_iterator(other.values.begin()),
                  std::make_move_iterator(other.values.end()));
    positions.reset();
  }
  template <class Keep> void retain(Keep keep) {
    positions.reset();
    std::size_t written = 0;
    for (std::size_t i = 0; i < values.size(); ++i)
      if (keep(edit(i))) {
        if (written != i)
          values[written] = std::move(values[i]);
        ++written;
      }
    values.resize(written);
  }

private:
  using Positions = std::unordered_map<const T *, std::size_t>;
  Storage values;
  mutable std::unique_ptr<Positions> positions;
};
} // namespace mettle
