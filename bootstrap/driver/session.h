#pragma once

#include <iosfwd>

namespace mettle::driver {
int compilationServer(std::istream &input, std::ostream &output);
}
