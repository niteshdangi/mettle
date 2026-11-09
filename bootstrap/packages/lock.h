#pragma once

#include "diagnostics/diagnostics.h"
#include "packages/data.h"
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace mettle::packages {
// One resolved package: exact version, source identity, content checksum,
// the selected features and the active dependency edges (by package identity).
struct LockedPackage {
  std::string id, name, version, source, checksum;
  std::vector<std::string> features, dependencies;
  // The entry in the parsed lock file (empty for a freshly resolved lock).
  Span span;
};

// Equal in everything the lock records (not where it was read from).
bool equivalent(const LockedPackage &left, const LockedPackage &right);

struct Lock {
  static constexpr std::int64_t format = 2;
  // The root package first, then the rest sorted by identity.
  std::vector<LockedPackage> packages;

  const LockedPackage *find(const std::string &id) const;
};

// Deterministic lock.mettle text.
std::string serialize(const Lock &lock);
// Validates a parsed lock.mettle; every fault is a `lock` diagnostic.
std::optional<Lock> parseLock(const data::Value &root, const Source &source,
                              Diagnostics &diagnostics);
// What differs between a recorded lock and a freshly resolved one.
std::vector<std::string> differences(const Lock &recorded, const Lock &fresh);
} // namespace mettle::packages
