#pragma once

#include "documentation/document.h"
#include <string>
#include <vector>

namespace mettle::documentation {
struct File {
  std::string name, content;
};

// The static site for `pages`: `index.html`, `style.css` and one
// `<module>.html` per page. The output depends only on the pages (items are
// sorted, nothing records time or environment) and needs no script, font or
// network access.
std::vector<File> render(std::vector<Page> pages);
} // namespace mettle::documentation
