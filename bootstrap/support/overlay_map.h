#pragma once

#include <cstddef>
#include <functional>
#include <initializer_list>
#include <iterator>
#include <map>
#include <memory>
#include <utility>

namespace mettle {
template <class K, class V> class OverlayMap {
  using Storage = std::map<K, V>;

public:
  using key_type = K;
  using mapped_type = V;
  using value_type = typename Storage::value_type;
  class Iterator {
  public:
    using iterator_category = std::forward_iterator_tag;
    using value_type = typename Storage::value_type;
    using difference_type = std::ptrdiff_t;
    using reference = const value_type &;
    using pointer = const value_type *;
    Iterator() = default;
    reference operator*() const { return localSelected() ? *local : *base; }
    pointer operator->() const { return &**this; }
    Iterator &operator++() {
      if (base != baseEnd && local != localEnd && base->first == local->first) {
        ++base;
        ++local;
      } else if (localSelected())
        ++local;
      else
        ++base;
      return *this;
    }
    Iterator operator++(int) {
      auto previous = *this;
      ++*this;
      return previous;
    }
    bool operator==(const Iterator &) const = default;

  private:
    friend class OverlayMap;
    using Position = typename Storage::const_iterator;
    Iterator(Position base, Position baseEnd, Position local, Position localEnd)
        : base(base), baseEnd(baseEnd), local(local), localEnd(localEnd) {}
    bool localSelected() const {
      return local != localEnd &&
             (base == baseEnd || !std::less<K>{}(base->first, local->first));
    }
    Position base, baseEnd, local, localEnd;
  };
  OverlayMap() = default;
  OverlayMap(const OverlayMap &) = default;
  OverlayMap &operator=(const OverlayMap &) = default;
  OverlayMap(OverlayMap &&other) noexcept
      : base(std::move(other.base)), local(std::move(other.local)),
        count(std::exchange(other.count, 0)) {}
  OverlayMap &operator=(OverlayMap &&other) noexcept {
    if (this != &other) {
      base = std::move(other.base);
      local = std::move(other.local);
      count = std::exchange(other.count, 0);
    }
    return *this;
  }
  OverlayMap(std::initializer_list<value_type> values)
      : local(values), count(local.size()) {}
  Iterator begin() const {
    return {prefix().begin(), prefix().end(), local.begin(), local.end()};
  }
  Iterator end() const {
    return {prefix().end(), prefix().end(), local.end(), local.end()};
  }
  Iterator find(const K &key) const {
    const auto &shared = prefix();
    auto inherited = shared.lower_bound(key);
    auto own = local.lower_bound(key);
    auto less = std::less<K>{};
    if ((inherited == shared.end() || less(key, inherited->first)) &&
        (own == local.end() || less(key, own->first)))
      return end();
    return {inherited, shared.end(), own, local.end()};
  }
  bool contains(const K &key) const {
    return local.contains(key) || prefix().contains(key);
  }
  const V &at(const K &key) const {
    auto own = local.find(key);
    return own == local.end() ? prefix().at(key) : own->second;
  }
  V &operator[](const K &key) {
    auto own = local.find(key);
    if (own != local.end())
      return own->second;
    auto imported = prefix().find(key);
    if (imported != prefix().end())
      return local.emplace(key, imported->second).first->second;
    auto [position, inserted] = local.try_emplace(key);
    count += inserted;
    return position->second;
  }
  template <class... Args>
  std::pair<Iterator, bool> emplace(K key, Args &&...args) {
    const auto &shared = prefix();
    auto inherited = shared.lower_bound(key);
    if (inherited != shared.end() && !std::less<K>{}(key, inherited->first))
      return {{inherited, shared.end(), local.lower_bound(key), local.end()},
              false};
    auto [position, inserted] =
        local.try_emplace(std::move(key), std::forward<Args>(args)...);
    count += inserted;
    return {{inherited, shared.end(), position, local.end()}, inserted};
  }
  template <class Input> void insert(Input first, Input last) {
    for (; first != last; ++first)
      emplace(first->first, first->second);
  }
  std::size_t size() const { return count; }
  bool empty() const { return count == 0; }
  void clear() {
    base.reset();
    local.clear();
    count = 0;
  }
  void freeze() {
    if (local.empty())
      return;
    if (!base) {
      base = std::make_shared<const Storage>(std::move(local));
      local.clear();
      return;
    }
    auto merged = std::make_shared<Storage>(prefix());
    for (auto &[key, value] : local)
      merged->insert_or_assign(key, std::move(value));
    base = std::move(merged);
    local.clear();
  }

private:
  const Storage &prefix() const {
    static const Storage empty;
    return base ? *base : empty;
  }
  std::shared_ptr<const Storage> base;
  Storage local;
  std::size_t count = 0;
};
} // namespace mettle
