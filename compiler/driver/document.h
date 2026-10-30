#pragma once

#include "driver/options.h"

namespace mettle::driver {
// `mettle doc [PATH...] [-o DIR] [--private]`: writes the static HTML
// documentation of the .mt files under the paths.
int document(const Options &options);
} // namespace mettle::driver
