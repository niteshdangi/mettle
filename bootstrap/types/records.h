#pragma once

#include <algorithm>
#include <array>
#include <atomic>
#include <cstddef>
#include <functional>
#include <initializer_list>
#include <iterator>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <type_traits>
#include <utility>
#include <vector>

namespace mettle {
// Copies share immutable pages; a write detaches its page before exposing it.
template <class T, bool ExplicitWrite = false> class TypeRecords {
public:
  using Loader = std::function<T(std::size_t)>;
  using Reference = std::conditional_t<ExplicitWrite, const T &, T &>;
  template <bool Constant> class Iterator {
    using Owner = std::conditional_t<Constant, const TypeRecords, TypeRecords>;

  public:
    using iterator_category = std::forward_iterator_tag;
    using value_type = T;
    using difference_type = std::ptrdiff_t;
    using reference =
        std::conditional_t<Constant || ExplicitWrite, const T &, T &>;
    using pointer =
        std::conditional_t<Constant || ExplicitWrite, const T *, T *>;
    Iterator() = default;
    reference operator*() const { return (*owner)[index]; }
    pointer operator->() const { return &**this; }
    Iterator &operator++() {
      ++index;
      return *this;
    }
    Iterator operator++(int) {
      auto old = *this;
      ++*this;
      return old;
    }
    bool operator==(const Iterator &) const = default;

  private:
    friend class TypeRecords;
    Iterator(Owner *owner, std::size_t index) : owner(owner), index(index) {}
    Owner *owner = nullptr;
    std::size_t index = 0;
  };
  Iterator<false> begin() { return {this, 0}; }
  Iterator<false> end() { return {this, count}; }
  Iterator<true> begin() const { return {this, 0}; }
  Iterator<true> end() const { return {this, count}; }
  TypeRecords() = default;
  TypeRecords(std::initializer_list<T> values) {
    reserve(values.size());
    for (const auto &value : values)
      push_back(value);
  }
  TypeRecords(const TypeRecords &) = default;
  TypeRecords &operator=(const TypeRecords &) = default;
  TypeRecords(TypeRecords &&other) noexcept
      : pages(std::move(other.pages)), count(std::exchange(other.count, 0)) {}
  TypeRecords &operator=(TypeRecords &&other) noexcept {
    if (this != &other) {
      pages = std::move(other.pages);
      count = std::exchange(other.count, 0);
    }
    return *this;
  }
  std::size_t size() const { return count; }
  bool empty() const { return count == 0; }
  bool isMaterialized(std::size_t index) const {
    if (index >= count)
      throw std::out_of_range("type record index");
    return pages[index / pageCapacity]->ready[index % pageCapacity].load(
        std::memory_order_acquire);
  }
  const T &front() const { return (*this)[0]; }
  Reference front() { return (*this)[0]; }
  const T &operator[](std::size_t index) const {
    return pages[index / pageCapacity]->read(index % pageCapacity);
  }
  Reference operator[](std::size_t index) {
    if constexpr (ExplicitWrite)
      return std::as_const(*this)[index];
    else
      return writable(index / pageCapacity).get(index % pageCapacity);
  }
  T &edit(std::size_t index) {
    if (index >= count)
      throw std::out_of_range("type record index");
    return writable(index / pageCapacity).get(index % pageCapacity);
  }
  const T &at(std::size_t index) const {
    if (index >= count)
      throw std::out_of_range("type record index");
    return (*this)[index];
  }
  std::shared_ptr<const T> retain(std::size_t index) const {
    if (index >= count)
      throw std::out_of_range("type record index");
    const auto &page = pages[index / pageCapacity];
    return {page, &page->read(index % pageCapacity)};
  }
  Reference at(std::size_t index) {
    if (index >= count)
      throw std::out_of_range("type record index");
    return (*this)[index];
  }
  const T &back() const { return (*this)[count - 1]; }
  Reference back() { return (*this)[count - 1]; }
  void push_back(T value) {
    push_uninitialized();
    edit(count - 1) = std::move(value);
  }
  template <class... Args> T &emplace_back(Args &&...args) {
    push_back(T(std::forward<Args>(args)...));
    return edit(count - 1);
  }
  void reserve(std::size_t capacity) {
    pages.reserve(capacity / pageCapacity + (capacity % pageCapacity != 0));
  }
  void resize(std::size_t size) {
    if (size < count) {
      pages.resize(size / pageCapacity + (size % pageCapacity != 0));
      if (size % pageCapacity) {
        auto &page = writable(size / pageCapacity);
        for (auto i = size % pageCapacity; i < pageCapacity; ++i) {
          if (!page.items.empty())
            page.items[i] = T{};
          page.ready[i].store(false, std::memory_order_relaxed);
          if (!page.pending.empty())
            page.pending[i] = {};
        }
      }
      count = size;
    } else
      while (count < size)
        push_uninitialized();
  }
  void clear() {
    pages.clear();
    count = 0;
  }
  bool operator==(const TypeRecords &other) const {
    return size() == other.size() && std::equal(begin(), end(), other.begin());
  }
  void push_shared(std::shared_ptr<const T> record) {
    if (!record)
      throw std::invalid_argument("cannot share an empty record");
    push_uninitialized();
    auto &page = writable((count - 1) / pageCapacity);
    if (page.pending.empty())
      page.pending.resize(pageCapacity);
    page.pending[(count - 1) % pageCapacity].borrowed = std::move(record);
  }
  void push_uninitialized() {
    if (count % pageCapacity == 0)
      pages.push_back(std::make_shared<Page>());
    ++count;
  }
  void defer(std::size_t index, std::size_t input,
             std::shared_ptr<const Loader> loader) {
    if (index >= count || !loader)
      throw std::invalid_argument("invalid deferred type record");
    auto &page = writable(index / pageCapacity);
    auto slot = index % pageCapacity;
    if (page.ready[slot].load(std::memory_order_acquire))
      throw std::logic_error("cannot defer a materialized type record");
    if (page.pending.empty())
      page.pending.resize(pageCapacity);
    page.pending[slot] = {std::move(loader), input, {}};
  }

private:
  static constexpr std::size_t pageCapacity =
      std::max<std::size_t>(1, 4096 / sizeof(T));
  struct Page {
    struct Deferred {
      std::shared_ptr<const Loader> loader;
      std::size_t input = 0;
      std::shared_ptr<const T> borrowed;
    };
    mutable std::vector<T> items;
    mutable std::array<std::atomic_bool, pageCapacity> ready{};
    mutable std::mutex mutex;
    mutable std::vector<Deferred> pending;
    Page() = default;
    Page(const Page &other) {
      std::lock_guard lock(other.mutex);
      items = other.items;
      pending = other.pending;
      for (std::size_t i = 0; i < pageCapacity; ++i)
        ready[i].store(other.ready[i].load(std::memory_order_relaxed),
                       std::memory_order_relaxed);
    }
    const T &read(std::size_t index) const {
      if (!ready[index].load(std::memory_order_acquire) && !pending.empty() &&
          pending[index].borrowed)
        return *pending[index].borrowed;
      return get(index);
    }
    T &get(std::size_t index) const {
      if (!ready[index].load(std::memory_order_acquire)) {
        std::lock_guard lock(mutex);
        if (!ready[index].load(std::memory_order_relaxed)) {
          if (items.empty())
            items.resize(pageCapacity);
          if (!pending.empty()) {
            if (pending[index].borrowed)
              items[index] = *pending[index].borrowed;
            else if (pending[index].loader)
              items[index] = (*pending[index].loader)(pending[index].input);
            pending[index].loader.reset();
          }
          ready[index].store(true, std::memory_order_release);
        }
      }
      return items[index];
    }
  };
  std::vector<std::shared_ptr<Page>> pages;
  std::size_t count = 0;
  Page &writable(std::size_t index) {
    auto &page = pages[index];
    if (!page.unique())
      page = std::make_shared<Page>(*page);
    return *page;
  }
};
} // namespace mettle
