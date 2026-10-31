#pragma once

#include "documentation/document.h"
#include <functional>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace mettle::documentation {
struct File {
  std::string name, content;
};
using ReferenceResolver =
    std::function<std::optional<std::string>(std::uint32_t, Span,
                                             std::string_view)>;

// The static site for `pages`: `index.html`, `style.css` and one
// `<module>.html` per page. The output depends only on the pages (items are
// sorted, nothing records time or environment) and needs no script, font or
// network access.
std::vector<File> render(std::vector<Page> pages,
                         const ReferenceResolver &resolve = {});
} // namespace mettle::documentation
