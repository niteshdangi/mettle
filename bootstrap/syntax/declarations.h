#pragma once

#include <atomic>
#include <compare>
#include <functional>
#include <initializer_list>
#include <iterator>
#include <map>
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
  struct Indexed : std::enable_shared_from_this<Indexed> {
    std::size_t count;
    std::function<Record(std::size_t)> load;
    mutable std::mutex mutex;
    mutable std::map<std::size_t, Record> records;
    std::vector<Observer> observers;
    Indexed(std::size_t count, std::function<Record(std::size_t)> load)
        : count(count), load(std::move(load)) {}
    Record &record(std::size_t index) const {
      Record *value;
      bool inserted = false;
      {
        std::lock_guard lock(mutex);
        auto found = records.find(index);
        if (found == records.end()) {
          found = records.emplace(index, load(index)).first;
          inserted = true;
        }
        value = &found->second;
      }
      if (inserted && value->deferred) {
        auto observe = [owner = this->weak_from_this(),
                        index](std::shared_ptr<const T> value) {
          if (auto retained = owner.lock()) {
            std::vector<Observer> callbacks;
            {
              std::lock_guard lock(retained->mutex);
              callbacks = retained->observers;
            }
            for (const auto &callback : callbacks)
              callback(index, value);
          }
        };
        auto &state = value->deferred->synchronize();
        std::shared_ptr<const T> ready;
        {
          std::lock_guard lock(state.mutex);
          ready = state.value;
          if (!ready)
            state.observers.push_back(observe);
        }
        if (ready)
          observe(std::move(ready));
      }
      return *value;
    }
  };

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
      return headers ? owner->header(position) : owner->at(position);
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
      return static_cast<difference_type>(left.position) -
             static_cast<difference_type>(right.position);
    }
    auto operator<=>(const Iterator &) const = default;

  private:
    friend class Declarations;
    explicit Iterator(const Declarations *owner, std::size_t position,
                      bool headers = false)
        : owner(owner), position(position), headers(headers) {}
    const Declarations *owner = nullptr;
    std::size_t position = 0;
    bool headers = false;
  };
  class Headers {
  public:
    Iterator begin() const { return Iterator(&owner, beginIndex, true); }
    Iterator end() const { return Iterator(&owner, owner.size(), true); }

  private:
    friend class Declarations;
    explicit Headers(const Declarations &owner, std::size_t beginIndex = 0)
        : owner(owner), beginIndex(beginIndex) {}
    const Declarations &owner;
    std::size_t beginIndex;
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
        index = owner.localIndex(index);
        while (index < owner.size() && owner.header(index).item.checkedImport) {
          ++index;
          index = owner.localIndex(index);
        }
      }
      Declarations &owner;
      std::size_t index;
    };
    Iterator begin() { return {owner, owner.nativeSize()}; }
    Iterator end() { return {owner, owner.size()}; }

  private:
    friend class Declarations;
    explicit Local(Declarations &owner) : owner(owner) {}
    Declarations &owner;
  };
  class LocalHeaders {
  public:
    class Iterator {
    public:
      using iterator_category = std::forward_iterator_tag;
      using value_type = T;
      using difference_type = std::ptrdiff_t;
      using reference = const T &;
      using pointer = const T *;
      Iterator() = default;
      reference operator*() const { return owner->header(index); }
      pointer operator->() const { return &**this; }
      Iterator &operator++() {
        ++index;
        skip();
        return *this;
      }
      Iterator operator++(int) {
        auto previous = *this;
        ++*this;
        return previous;
      }
      bool operator==(const Iterator &) const = default;

    private:
      friend class LocalHeaders;
      Iterator(const Declarations *owner, std::size_t index)
          : owner(owner), index(index) {
        skip();
      }
      void skip() { index = owner->localIndex(index); }
      const Declarations *owner = nullptr;
      std::size_t index = 0;
    };
    Iterator begin() const { return {&owner, owner.nativeSize()}; }
    Iterator end() const { return {&owner, owner.size()}; }

  private:
    friend class Declarations;
    explicit LocalHeaders(const Declarations &owner) : owner(owner) {}
    const Declarations &owner;
  };
  Declarations() = default;
  Declarations(std::initializer_list<T> values) {
    reserve(values.size());
    for (const auto &value : values)
      push_back(value);
  }
  Declarations(const Declarations &other) {
    indexed = other.indexed;
    overrides = other.overrides;
    if (other.suffix)
      suffix = std::make_shared<Declarations>(*other.suffix);
    values.reserve(other.values.size());
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
  Iterator begin() const { return Iterator(this, 0); }
  Iterator end() const { return Iterator(this, size()); }
  Headers headers() const { return Headers(*this); }
  LocalHeaders localHeaders() const { return LocalHeaders(*this); }
  std::size_t nativeSize() const { return indexed ? indexed->count : 0; }
  bool native(std::size_t index) const {
    return index < nativeSize() || (suffix && index >= suffixBegin() &&
                                    suffix->native(index - suffixBegin()));
  }
  std::size_t admittedSize() const {
    const auto suffixCount = suffix ? suffix->admittedSize() : 0;
    if (!indexed)
      return values.size() + suffixCount;
    std::lock_guard lock(indexed->mutex);
    return indexed->records.size() + values.size() + suffixCount;
  }
  template <class Visit> void nativeOverrides(Visit visit) const {
    std::size_t offset = 0;
    for (auto *owner = this; owner; owner = owner->suffix.get()) {
      for (const auto &[index, value] : owner->overrides)
        visit(offset + index, *value.header,
              *owner->indexed->record(index).header);
      offset += owner->suffixBegin();
    }
  }
  void mountIndexed(std::size_t count, Loader header, Loader load) {
    if (!empty())
      throw std::logic_error("indexed declarations require an empty table");
    indexed = std::make_shared<Indexed>(count, [header = std::move(header),
                                                load = std::move(load)](
                                                   std::size_t index) {
      auto batch =
          deferredLoader(1, [load, index](std::size_t) { return load(index); });
      auto &value = batch->headers[0].emplace(header(index));
      return Record{{batch, &value}, {batch, &batch->records[0]}};
    });
  }
  const T &header(std::size_t index) const { return *record(index).header; }
  std::shared_ptr<const T> sharedHeader(std::size_t index) const {
    return record(index).header;
  }
  Local local() { return Local(*this); }
  std::size_t size() const {
    return suffixBegin() + (suffix ? suffix->size() : 0);
  }
  bool empty() const { return size() == 0; }
  const T &operator[](std::size_t index) const { return *record(index).get(); }
  const T &at(std::size_t index) const { return *record(index).get(); }
  const T &front() const { return at(0); }
  const T &back() const { return at(size() - 1); }
  std::shared_ptr<const T> shared(std::size_t index) const {
    return record(index).get();
  }
  bool isMaterialized(std::size_t index) const {
    if (suffix && index >= suffixBegin())
      return suffix->isMaterialized(index - suffixBegin());
    if (auto found = overrides.find(index); found != overrides.end())
      return !found->second.deferred || found->second.deferred->ready();
    if (native(index)) {
      std::lock_guard lock(indexed->mutex);
      auto found = indexed->records.find(index);
      return found != indexed->records.end() &&
             (!found->second.deferred || found->second.deferred->ready());
    }
    const auto &value = record(index);
    return !value.deferred || value.deferred->ready();
  }
  void
  onMaterialize(std::size_t index,
                std::function<void(std::shared_ptr<const T>)> observe) const {
    const auto &value = record(index);
    if (!value.deferred) {
      observe(value.header);
      return;
    }
    auto &state = value.deferred->synchronize();
    std::lock_guard lock(state.mutex);
    if (state.value)
      observe(state.value);
    else
      state.observers.push_back(std::move(observe));
  }
  void onMaterializeAll(Observer observer) const {
    auto shared = std::make_shared<const Observer>(std::move(observer));
    if (indexed) {
      std::vector<std::pair<std::size_t, std::shared_ptr<const T>>> ready;
      {
        std::lock_guard lock(indexed->mutex);
        indexed->observers.push_back(*shared);
        for (const auto &[index, value] : indexed->records)
          if (!value.deferred || value.deferred->ready())
            ready.emplace_back(index, value.get());
      }
      for (auto &[index, value] : ready)
        (*shared)(index, std::move(value));
    }
    for (std::size_t i = 0; i < values.size();) {
      if (!values[i].deferred) {
        (*shared)(nativeSize() + i, values[i].header);
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
          [shared, begin = begin + nativeSize(), first = first.index,
           count = i - begin](std::size_t index,
                              std::shared_ptr<const T> value) {
            if (index >= first && index - first < count)
              (*shared)(begin + index - first, std::move(value));
          });
    }
    if (suffix)
      suffix->onMaterializeAll(
          [shared, offset = suffixBegin()](std::size_t index,
                                           std::shared_ptr<const T> value) {
            (*shared)(offset + index, std::move(value));
          });
  }
  static auto deferredLoader(std::size_t count, Loader load) {
    return std::make_shared<Batch>(count, std::move(load));
  }
  void push_deferred(T header, const std::shared_ptr<Batch> &batch,
                     std::size_t index) {
    if (suffix) {
      suffix->push_deferred(std::move(header), batch, index);
      return;
    }
    if (index >= batch->count)
      throw std::out_of_range("deferred declaration index");
    if (batch->headers[index])
      throw std::logic_error("deferred declaration is already mounted");
    auto &value = batch->headers[index].emplace(std::move(header));
    values.push_back({{batch, &value}, {batch, &batch->records[index]}});
    positions.reset();
  }
  T &emplace_deferred(const std::shared_ptr<Batch> &batch, std::size_t index) {
    if (suffix)
      return suffix->emplace_deferred(batch, index);
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
    if (suffix && index >= suffixBegin()) {
      suffix->transformHeader(index - suffixBegin(), std::move(transform));
      return;
    }
    auto &value = writableRecord(index);
    if (!value.deferred) {
      transform(edit(index));
      return;
    }
    auto previous = value;
    auto header = std::make_shared<T>(*value.header);
    transform(*header);
    auto batch =
        deferredLoader(1, [previous = std::move(previous),
                           transform = std::move(transform)](std::size_t) {
          T value = *previous.get();
          transform(value);
          return value;
        });
    value = {std::move(header), {batch, &batch->records[0]}};
    positions.reset();
  }
  T &edit(std::size_t index) {
    if (suffix && index >= suffixBegin())
      return suffix->edit(index - suffixBegin());
    auto &entry = writableRecord(index);
    if (entry.deferred) {
      auto value = entry.get();
      entry = {std::move(value), {}};
      positions.reset();
    }
    auto &value = entry.header;
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
      indexed->reserve(admittedSize());
      if (this->indexed) {
        std::lock_guard lock(this->indexed->mutex);
        for (const auto &[index, value] : this->indexed->records) {
          indexed->emplace(value.header.get(), index);
          if (!value.deferred || value.deferred->ready())
            indexed->emplace(value.get().get(), index);
        }
      }
      for (std::size_t i = 0; i < values.size(); ++i) {
        indexed->emplace(values[i].header.get(), i + nativeSize());
        if (isMaterialized(i + nativeSize()))
          indexed->emplace(values[i].get().get(), i + nativeSize());
      }
      for (const auto &[index, value] : overrides) {
        indexed->emplace(value.header.get(), index);
        if (!value.deferred || value.deferred->ready())
          indexed->emplace(value.get().get(), index);
      }
      positions = std::move(indexed);
    }
    auto found = positions->find(value);
    if (found == positions->end()) {
      for (const auto &[index, entry] : overrides)
        if (entry.header.get() == value ||
            ((!entry.deferred || entry.deferred->ready()) &&
             entry.get().get() == value)) {
          positions->emplace(value, index);
          return index;
        }
      if (indexed) {
        std::lock_guard lock(indexed->mutex);
        for (const auto &[index, entry] : indexed->records)
          if (entry.header.get() == value ||
              ((!entry.deferred || entry.deferred->ready()) &&
               entry.get().get() == value)) {
            positions->emplace(value, index);
            return index;
          }
      }
      for (std::size_t i = 0; i < values.size(); ++i)
        if (isMaterialized(i + nativeSize()) &&
            values[i].get().get() == value) {
          positions->emplace(value, i + nativeSize());
          return i + nativeSize();
        }
      if (suffix)
        return suffixBegin() + suffix->indexOf(value);
      throw std::out_of_range("declaration does not belong to this module");
    }
    return found->second;
  }
  void reserve(std::size_t count) {
    if (suffix) {
      if (count > suffixBegin())
        suffix->reserve(count - suffixBegin());
      return;
    }
    if (count > nativeSize())
      values.reserve(count - nativeSize());
  }
  void push_back(T value) {
    if (suffix) {
      suffix->push_back(std::move(value));
      return;
    }
    auto record = std::make_shared<T>(std::move(value));
    positions.reset();
    values.push_back({std::move(record), {}});
  }
  void resize(std::size_t count) {
    if (suffix) {
      if (count < suffixBegin())
        throw std::logic_error("cannot truncate native declaration identities");
      suffix->resize(count - suffixBegin());
      return;
    }
    if (count < size()) {
      if (count < nativeSize())
        throw std::logic_error("cannot truncate native declaration identities");
      values.resize(count - nativeSize());
      positions.reset();
    } else
      while (size() < count)
        push_back(T{});
  }
  void clear() {
    values.clear();
    indexed.reset();
    suffix.reset();
    overrides.clear();
    positions.reset();
  }
  void append(Declarations other) {
    if (suffix) {
      suffix->append(std::move(other));
      return;
    }
    if (other.indexed && !values.empty()) {
      suffix = std::make_shared<Declarations>(std::move(other));
      return;
    }
    auto offset = nativeSize();
    if (other.indexed) {
      if (!indexed)
        indexed = std::move(other.indexed);
      else {
        auto first = std::move(indexed);
        auto second = std::move(other.indexed);
        auto count = first->count + second->count;
        indexed = std::make_shared<Indexed>(count, [first,
                                                    second](std::size_t index) {
          return index < first->count ? first->record(index)
                                      : second->record(index - first->count);
        });
      }
      for (auto &[index, value] : other.overrides)
        overrides.emplace(index + offset, std::move(value));
    }
    values.insert(values.end(), std::make_move_iterator(other.values.begin()),
                  std::make_move_iterator(other.values.end()));
    suffix = std::move(other.suffix);
    positions.reset();
  }
  template <class Keep> void retain(Keep keep) {
    if (indexed || suffix)
      throw std::logic_error("cannot renumber native declaration identities");
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
  std::shared_ptr<Indexed> indexed;
  std::shared_ptr<Declarations> suffix;
  std::map<std::size_t, Record> overrides;
  mutable std::unique_ptr<Positions> positions;
  std::size_t suffixBegin() const { return nativeSize() + values.size(); }
  std::size_t localIndex(std::size_t index) const {
    if (index < nativeSize())
      return nativeSize();
    return suffix && index >= suffixBegin()
               ? suffixBegin() + suffix->localIndex(index - suffixBegin())
               : index;
  }
  const Record &record(std::size_t index) const {
    if (suffix && index >= suffixBegin())
      return suffix->record(index - suffixBegin());
    if (auto found = overrides.find(index); found != overrides.end())
      return found->second;
    return native(index) ? indexed->record(index)
                         : values.at(index - nativeSize());
  }
  Record &writableRecord(std::size_t index) {
    if (suffix && index >= suffixBegin())
      return suffix->writableRecord(index - suffixBegin());
    if (native(index))
      return overrides.try_emplace(index, record(index)).first->second;
    return values.at(index - nativeSize());
  }
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
