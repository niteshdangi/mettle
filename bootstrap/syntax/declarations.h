#pragma once

#include <atomic>
#include <compare>
#include <functional>
#include <initializer_list>
#include <iterator>
#include <memory>
#include <mutex>
#include <optional>
#include <stdexcept>
#include <unordered_map>
#include <utility>
#include <vector>

namespace mettle {
template <class T> class Declarations {
  using Observer = std::function<void(std::size_t, std::shared_ptr<const T>)>;
  struct Batch;
  struct Deferred {
    struct State {
      std::once_flag once;
      std::shared_ptr<T> value;
      std::atomic<bool> ready = false;
      std::mutex mutex;
      std::vector<std::function<void(std::shared_ptr<const T>)>> observers;
    };
    Batch *owner = nullptr;
    std::size_t index = 0;
    std::unique_ptr<State> owned;
    std::atomic<State *> state = nullptr;
    State &synchronize();
    bool ready() const {
      auto *current = state.load(std::memory_order_acquire);
      return current && current->ready.load(std::memory_order_acquire);
    }
    const std::shared_ptr<T> &get();
  };
  struct Batch {
    std::function<T(std::size_t)> load;
    std::size_t count;
    std::vector<std::optional<T>> headers;
    std::unique_ptr<Deferred[]> records;
    std::mutex mutex;
    std::vector<Observer> observers;
    Batch(std::size_t count, std::function<T(std::size_t)> load)
        : load(std::move(load)), count(count), headers(count),
          records(std::make_unique<Deferred[]>(count)) {
      for (std::size_t i = 0; i < count; ++i) {
        records[i].owner = this;
        records[i].index = i;
      }
    }
    void observe(std::size_t begin, std::size_t end, Observer observer) {
      std::lock_guard lock(mutex);
      observers.push_back(std::move(observer));
      for (std::size_t i = begin; i < end; ++i)
        if (records[i].ready())
          observers.back()(
              i, records[i].state.load(std::memory_order_relaxed)->value);
    }
  };
  struct Record {
    std::shared_ptr<T> header;
    std::shared_ptr<Deferred> deferred;
    const std::shared_ptr<T> &get() const {
      return deferred ? deferred->get() : header;
    }
  };
  using Storage = std::vector<Record>;

public:
  using value_type = T;
  using Loader = std::function<T(std::size_t)>;
  class Iterator {
  public:
    using iterator_category = std::random_access_iterator_tag;
    using value_type = T;
    using difference_type = std::ptrdiff_t;
    using reference = const T &;
    using pointer = const T *;
    Iterator() = default;
    reference operator*() const {
      return headers ? *position->header : *position->get();
    }
    pointer operator->() const { return &**this; }
    reference operator[](difference_type offset) const {
      return *(*this + offset);
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
    explicit Iterator(typename Storage::const_iterator position,
                      bool headers = false)
        : position(position), headers(headers) {}
    typename Storage::const_iterator position;
    bool headers = false;
  };
  class Headers {
  public:
    Iterator begin() const { return Iterator(owner.values.begin(), true); }
    Iterator end() const { return Iterator(owner.values.end(), true); }

  private:
    friend class Declarations;
    explicit Headers(const Declarations &owner) : owner(owner) {}
    const Declarations &owner;
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
        while (index < owner.size() && owner.header(index).item.checkedImport)
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
      values.push_back(value.header->item.checkedImport
                           ? value
                           : Record{std::make_shared<T>(*value.get()), {}});
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
  Headers headers() const { return Headers(*this); }
  const T &header(std::size_t index) const { return *values.at(index).header; }
  std::shared_ptr<const T> sharedHeader(std::size_t index) const {
    return values.at(index).header;
  }
  Local local() { return Local(*this); }
  std::size_t size() const { return values.size(); }
  bool empty() const { return values.empty(); }
  const T &operator[](std::size_t index) const { return *values[index].get(); }
  const T &at(std::size_t index) const { return *values.at(index).get(); }
  const T &front() const { return *values.front().get(); }
  const T &back() const { return *values.back().get(); }
  std::shared_ptr<const T> shared(std::size_t index) const {
    return values.at(index).get();
  }
  bool isMaterialized(std::size_t index) const {
    const auto &record = values.at(index);
    return !record.deferred || record.deferred->ready();
  }
  void
  onMaterialize(std::size_t index,
                std::function<void(std::shared_ptr<const T>)> observe) const {
    const auto &record = values.at(index);
    if (!record.deferred) {
      observe(record.header);
      return;
    }
    auto &state = record.deferred->synchronize();
    std::lock_guard lock(state.mutex);
    if (state.value)
      observe(state.value);
    else
      state.observers.push_back(std::move(observe));
  }
  void onMaterializeAll(Observer observer) const {
    auto shared = std::make_shared<const Observer>(std::move(observer));
    for (std::size_t i = 0; i < values.size();) {
      if (!values[i].deferred) {
        (*shared)(i, values[i].header);
        ++i;
        continue;
      }
      const auto &first = *values[i].deferred;
      auto begin = i++;
      while (i < values.size() && values[i].deferred &&
             values[i].deferred->owner == first.owner &&
             values[i].deferred->index == first.index + i - begin)
        ++i;
      first.owner->observe(
          first.index, first.index + i - begin,
          [shared, begin, first = first.index, count = i - begin](
              std::size_t index, std::shared_ptr<const T> value) {
            if (index >= first && index - first < count)
              (*shared)(begin + index - first, std::move(value));
          });
    }
  }
  static auto deferredLoader(std::size_t count, Loader load) {
    return std::make_shared<Batch>(count, std::move(load));
  }
  void push_deferred(T header, const std::shared_ptr<Batch> &batch,
                     std::size_t index) {
    if (index >= batch->count)
      throw std::out_of_range("deferred declaration index");
    if (batch->headers[index])
      throw std::logic_error("deferred declaration is already mounted");
    auto &value = batch->headers[index].emplace(std::move(header));
    values.push_back({{batch, &value}, {batch, &batch->records[index]}});
    positions.reset();
  }
  T &emplace_deferred(const std::shared_ptr<Batch> &batch, std::size_t index) {
    if (index >= batch->count)
      throw std::out_of_range("deferred declaration index");
    if (batch->headers[index])
      throw std::logic_error("deferred declaration is already mounted");
    auto &value = batch->headers[index].emplace();
    values.push_back({{batch, &value}, {batch, &batch->records[index]}});
    positions.reset();
    return value;
  }
  void push_deferred(T header, std::function<T()> load) {
    auto batch = deferredLoader(
        1, [load = std::move(load)](std::size_t) { return load(); });
    push_deferred(std::move(header), batch, 0);
  }
  void transformHeader(std::size_t index, std::function<void(T &)> transform) {
    auto &record = values.at(index);
    if (!record.deferred) {
      transform(edit(index));
      return;
    }
    auto previous = record;
    auto header = std::make_shared<T>(*record.header);
    transform(*header);
    auto batch =
        deferredLoader(1, [previous = std::move(previous),
                           transform = std::move(transform)](std::size_t) {
          T value = *previous.get();
          transform(value);
          return value;
        });
    record = {std::move(header), {batch, &batch->records[0]}};
    positions.reset();
  }
  T &edit(std::size_t index) {
    auto &record = values.at(index);
    if (record.deferred) {
      auto value = record.get();
      record = {std::move(value), {}};
      positions.reset();
    }
    auto &value = record.header;
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
      for (std::size_t i = 0; i < values.size(); ++i) {
        indexed->emplace(values[i].header.get(), i);
        if (isMaterialized(i))
          indexed->emplace(values[i].get().get(), i);
      }
      positions = std::move(indexed);
    }
    auto found = positions->find(value);
    if (found == positions->end()) {
      for (std::size_t i = 0; i < values.size(); ++i)
        if (isMaterialized(i) && values[i].get().get() == value) {
          positions->emplace(value, i);
          return i;
        }
      throw std::out_of_range("declaration does not belong to this module");
    }
    return found->second;
  }
  void reserve(std::size_t count) { values.reserve(count); }
  void push_back(T value) {
    auto record = std::make_shared<T>(std::move(value));
    positions.reset();
    values.push_back({std::move(record), {}});
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
template <class T> auto Declarations<T>::Deferred::synchronize() -> State & {
  auto *current = state.load(std::memory_order_acquire);
  if (!current) {
    std::lock_guard lock(owner->mutex);
    current = state.load(std::memory_order_relaxed);
    if (!current) {
      owned = std::make_unique<State>();
      current = owned.get();
      state.store(current, std::memory_order_release);
    }
  }
  return *current;
}
template <class T> const std::shared_ptr<T> &Declarations<T>::Deferred::get() {
  auto &current = synchronize();
  std::call_once(current.once, [&] {
    auto loaded = std::make_shared<T>(owner->load(index));
    std::lock_guard lock(current.mutex);
    current.value = std::move(loaded);
    for (const auto &observe : current.observers)
      observe(current.value);
    current.observers.clear();
    std::lock_guard batchLock(owner->mutex);
    for (const auto &observe : owner->observers)
      observe(index, current.value);
    current.ready.store(true, std::memory_order_release);
  });
  return current.value;
}
} // namespace mettle
