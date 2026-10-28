#include "ir/ir.h"
#include <ostream>

namespace mettle::ir {
void print(const Program &program, std::ostream &out) {
  for (const auto &f : program.functions) {
    out << "fn " << f.name << ": " << program.types->name(f.result) << '\n';
    for (std::size_t b = 0; b < f.blocks.size(); ++b) {
      out << "  block " << b << '\n';
      for (const auto &i : f.blocks[b].instructions) {
        out << "    %" << i.result.id << ": ";
        if (i.result.access != Access::Owned)
          out << (i.result.access == Access::Read ? "read " : "mut ");
        out << program.types->name(i.result.type) << " op"
            << static_cast<int>(i.op) << ' ' << i.text;
        for (auto v : i.operands)
          out << " %" << v.id;
        if (i.place.root >= 0) {
          out << " @" << i.place.root;
          for (auto field : i.place.fields)
            if (field.kind == Projection::Kind::Dereference)
              out << ".*";
            else
              out << '.' << field.index;
        }
        out << '\n';
      }
      auto &exit = f.blocks[b].exit;
      out << "    exit" << static_cast<int>(exit.kind) << " %" << exit.value.id
          << " -> " << exit.first << ", " << exit.second << '\n';
    }
  }
}
} // namespace mettle::ir
