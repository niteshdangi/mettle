#include "ir/verify.h"
#include "ir/dominance.h"
#include <algorithm>
#include <functional>
#include <numeric>
#include <set>
#include <unordered_set>

namespace mettle::ir {
namespace {
bool scalar(Type type) {
  return type == Type::I32 || type == Type::Bool || type == Type::Unit;
}

bool function(const Function &f, const Program &program,
              Diagnostics &diagnostics) {
  auto known = [&](Type type) { return program.types->contains(type); };
  auto concrete = [&](Type type) { return known(type) && type != Type::Never; };
  bool valid = true;
  auto fail = [&](Span span, std::string message) {
    diagnostics.error("internal", span,
                      "invalid CFG in '" + f.name + "': " + message);
    valid = false;
  };
  if ((f.blocks.empty() && f.externalName.empty()) || !known(f.result) ||
      f.parameters > f.locals.size()) {
    fail({}, "invalid function signature or empty block list");
    return false;
  }
  for (const auto &local : f.locals)
    if (!known(local.type))
      fail(local.span, "unresolved local type");
  for (std::size_t p = 0; p < f.parameters; ++p) {
    auto mode = f.locals[p].mode;
    if (mode != ParameterMode::Value && mode != ParameterMode::Take &&
        mode != ParameterMode::Read && mode != ParameterMode::Mut)
      fail(f.locals[p].span, "invalid parameter mode");
    if (mode == ParameterMode::Value &&
        !program.types->isCopy(f.locals[p].type))
      fail(f.locals[p].span,
           "non-Copy value parameter requires an explicit consuming contract");
  }
  if (f.twoPhaseReceiver &&
      (f.parameters == 0 || f.locals[0].mode != ParameterMode::Mut))
    fail({}, "invalid two-phase receiver signature");
  for (std::size_t local = f.parameters; local < f.locals.size(); ++local)
    if (f.locals[local].mode != ParameterMode::Value)
      fail(f.locals[local].span,
           "parameter mode attached to owned local storage");
  if (!f.externalName.empty()) {
    if (!f.blocks.empty() || f.parameters != f.locals.size())
      fail({}, "external function has a body or owned locals");
    return valid;
  }
  if (f.scopes.empty() || f.scopes[0].parent != -1)
    fail({}, "invalid root scope");
  for (std::size_t s = 1; s < f.scopes.size(); ++s)
    if (f.scopes[s].parent < 0 ||
        static_cast<std::size_t>(f.scopes[s].parent) >= s)
      fail({}, "invalid scope parent");
  for (const auto &local : f.locals)
    if (local.scope < -2 || local.scope >= static_cast<int>(f.scopes.size()))
      fail(local.span, "invalid local scope");
  for (auto source : f.resultSources)
    if (source >= f.parameters)
      fail({}, "invalid result source");
  auto count = std::accumulate(f.blocks.begin(), f.blocks.end(), std::size_t{0},
                               [](std::size_t sum, const Block &block) {
                                 return sum + block.instructions.size();
                               });
  if (f.values < 0 || static_cast<std::size_t>(f.values) != count) {
    fail({}, "value count does not match definitions");
    return false;
  }
  struct Definition {
    int block = -1;
    std::size_t position = 0;
    Type type = Type::Unknown;
    Access access = Access::Owned;
  };
  std::vector<Definition> definitions(count);
  auto blockIndex = [&](int block) {
    return block >= 0 && static_cast<std::size_t>(block) < f.blocks.size();
  };
  for (std::size_t b = 0; b < f.blocks.size(); ++b) {
    const auto &block = f.blocks[b];
    for (std::size_t i = 0; i < block.instructions.size(); ++i) {
      const auto &n = block.instructions[i];
      if (n.result.id < 0 || static_cast<std::size_t>(n.result.id) >= count ||
          !known(n.result.type)) {
        fail(n.span, "invalid value definition");
        continue;
      }
      auto &definition = definitions[n.result.id];
      if (definition.block >= 0)
        fail(n.span, "duplicate value definition");
      definition = {static_cast<int>(b), i, n.result.type, n.result.access};
    }
    const auto &exit = block.exit;
    switch (exit.kind) {
    case Exit::Jump:
    case Exit::Branch:
      if (!blockIndex(exit.first) ||
          (exit.kind == Exit::Branch && !blockIndex(exit.second)))
        fail({}, "invalid successor block");
      break;
    case Exit::Return:
    case Exit::Unreachable:
      break;
    default:
      fail({}, "missing or unknown terminator");
      break;
    }
  }
  if (!valid)
    return false;
  for (const auto &definition : definitions)
    if (definition.block < 0)
      fail({}, "missing value definition");
  if (!valid)
    return false;
  Dominance graph(f);
  if (!graph.predecessors[0].empty())
    fail({}, "entry block has predecessors");
  auto value = [&](Value operand, int block, std::size_t position, Span span) {
    if (operand.id < 0 || static_cast<std::size_t>(operand.id) >= count) {
      fail(span, "invalid value operand");
      return;
    }
    const auto &definition = definitions[operand.id];
    if (operand.type != definition.type || operand.type == Type::Never ||
        operand.access != definition.access)
      fail(span, "operand type does not match an available value");
    if ((definition.block == block && definition.position >= position) ||
        (graph.reachable(block) && !graph.dominates(definition.block, block)))
      fail(span, "value definition does not dominate its use");
  };
  for (std::size_t b = 0; b < f.blocks.size(); ++b) {
    const auto &block = f.blocks[b];
    bool pastPhi = false;
    for (std::size_t i = 0; i < block.instructions.size(); ++i) {
      const auto &n = block.instructions[i];
      auto result = n.result.type;
      auto arity = [&](std::size_t wanted) {
        if (n.operands.size() != wanted) {
          fail(n.span, "invalid operand count");
          return false;
        }
        return true;
      };
      auto require = [&](bool condition) {
        if (!condition)
          fail(n.span, "invalid instruction types or operation");
      };
      auto slot = [&] {
        if (n.place.root < 0 ||
            static_cast<std::size_t>(n.place.root) >= f.locals.size()) {
          fail(n.span, "invalid local slot");
          return false;
        }
        if (!projectedType(*program.types, f.locals[n.place.root].type,
                           n.place.fields)) {
          fail(n.span, "invalid projected place");
          return false;
        }
        return true;
      };
      bool borrow = n.op == Op::BorrowRead || n.op == Op::BorrowMut ||
                    n.op == Op::ReserveMut;
      if (!borrow)
        require(n.result.access == Access::Owned);
      if (n.op != Op::Call && n.op != Op::CatchCall && n.op != Op::Activate)
        for (auto operand : n.operands)
          require(operand.access == Access::Owned);
      if (n.op != Op::Phi) {
        pastPhi = true;
        for (auto operand : n.operands)
          value(operand, static_cast<int>(b), i, n.span);
      }
      switch (n.op) {
      case Op::Constant:
        arity(0);
        require(scalar(result));
        if (result == Type::Bool)
          require(n.number == 0 || n.number == 1);
        break;
      case Op::Declare:
        arity(0);
        slot();
        require(n.place.fields.empty());
        require(result == Type::Unit);
        break;
      case Op::Load:
      case Op::Move:
      case Op::BorrowRead:
      case Op::BorrowMut:
      case Op::ReserveMut:
        arity(0);
        if (slot())
          require(result == *projectedType(*program.types,
                                           f.locals[n.place.root].type,
                                           n.place.fields) &&
                  concrete(result));
        if (n.op == Op::Load)
          require(program.types->isCopy(result));
        if (borrow)
          require(n.result.access ==
                  (n.op == Op::BorrowRead ? Access::Read : Access::Mut));
        break;
      case Op::ViewRead:
      case Op::ViewMut:
        arity(0);
        require(program.types->isView(result));
        if (slot() && program.types->isView(result)) {
          const auto &view = program.types->view(result);
          require(view.payload == *projectedType(*program.types,
                                                 f.locals[n.place.root].type,
                                                 n.place.fields) &&
                  view.mode == (n.op == Op::ViewRead ? ParameterMode::Read
                                                     : ParameterMode::Mut));
        }
        break;
      case Op::Activate:
        if (arity(1)) {
          require(n.operands[0].access == Access::Mut);
          auto id = n.operands[0].id;
          if (id >= 0 && static_cast<std::size_t>(id) < definitions.size()) {
            const auto &definition = definitions[id];
            require(f.blocks[definition.block]
                        .instructions[definition.position]
                        .op == Op::ReserveMut);
          }
        }
        require(result == Type::Unit);
        break;
      case Op::ScopeExit:
        arity(0);
        require(result == Type::Unit && n.number >= 0 &&
                n.number < static_cast<int>(f.scopes.size()));
        break;
      case Op::Store:
        if (arity(1) && slot())
          require(n.operands[0].type ==
                  *projectedType(*program.types, f.locals[n.place.root].type,
                                 n.place.fields));
        require(result == Type::Unit);
        break;
      case Op::Unary:
        if (arity(1)) {
          auto operand = n.operands[0].type;
          require(
              (n.text == "-" && operand == Type::I32 && result == Type::I32) ||
              (n.text == "!" &&
               (operand == Type::I32 || operand == Type::Bool) &&
               result == operand));
        }
        break;
      case Op::Binary:
        if (arity(2)) {
          auto a = n.operands[0].type, c = n.operands[1].type;
          bool compare = n.text == "==" || n.text == "!=" || n.text == "<" ||
                         n.text == "<=" || n.text == ">" || n.text == ">=";
          bool bit = n.text == "&" || n.text == "|" || n.text == "^";
          bool arithmetic = n.text == "+" || n.text == "-" || n.text == "*" ||
                            n.text == "/" || n.text == "%" || n.text == "<<" ||
                            n.text == ">>";
          require(
              a == c &&
              ((compare && scalar(a) && result == Type::Bool) ||
               (bit && (a == Type::Bool || a == Type::I32) && result == a) ||
               (arithmetic && a == Type::I32 && result == Type::I32)));
        }
        break;
      case Op::Call:
      case Op::CatchCall:
        if (n.callee < 0 ||
            static_cast<std::size_t>(n.callee) >= program.functions.size()) {
          fail(n.span, "invalid callee");
          break;
        case Op::Construct:
          require(program.types->isProduct(result));
          if (program.types->isProduct(result)) {
            const auto &fields = program.types->product(result).fields;
            if (arity(fields.size()))
              for (std::size_t p = 0; p < fields.size(); ++p)
                require(n.operands[p].type == fields[p].type);
          }
          break;
        case Op::Project:
          if (arity(1)) {
            auto base = n.operands[0].type;
            if (!program.types->isProduct(base)) {
              require(false);
              break;
            }
            const auto &fields = program.types->product(base).fields;
            if (n.number < 0 ||
                static_cast<std::size_t>(n.number) >= fields.size()) {
              fail(n.span, "invalid field projection");
              break;
            }
            require(result == fields[n.number].type);
            require(program.types->isCopy(result));
          }
          break;
        } else {
          const auto &callee = program.functions[n.callee];
          require(n.op == Op::CatchCall
                      ? result == Type::I32 && callee.result == Type::Unit
                      : result == callee.result);
          if (callee.parameters > callee.locals.size()) {
            fail(n.span, "invalid callee signature");
            break;
          }
          if (arity(callee.parameters))
            for (std::size_t p = 0; p < n.operands.size(); ++p) {
              require(n.operands[p].type == callee.locals[p].type);
              auto mode = callee.locals[p].mode;
              auto access = mode == ParameterMode::Read  ? Access::Read
                            : mode == ParameterMode::Mut ? Access::Mut
                                                         : Access::Owned;
              require(n.operands[p].access == access);
              auto id = n.operands[p].id;
              if (id >= 0 &&
                  static_cast<std::size_t>(id) < definitions.size()) {
                const auto &definition = definitions[id];
                if (f.blocks[definition.block]
                        .instructions[definition.position]
                        .op == Op::ReserveMut)
                  require(p == 0 && callee.twoPhaseReceiver);
              }
              if (access == Access::Mut)
                for (std::size_t previous = 0; previous < p; ++previous)
                  if (n.operands[previous].id == n.operands[p].id)
                    fail(n.span,
                         "exclusive loan value used for multiple parameters");
            }
          if (result == Type::Never)
            require(i + 1 == block.instructions.size() &&
                    block.exit.kind == Exit::Unreachable);
        }
        break;
      case Op::Phi: {
        require(!pastPhi && concrete(result) && !n.operands.empty());
        auto expected = graph.predecessors[b];
        auto actual = n.predecessors;
        std::sort(expected.begin(), expected.end());
        std::sort(actual.begin(), actual.end());
        require(expected == actual &&
                n.operands.size() == n.predecessors.size());
        for (std::size_t p = 0;
             p < n.operands.size() && p < n.predecessors.size(); ++p) {
          int predecessor = n.predecessors[p];
          if (!blockIndex(predecessor)) {
            fail(n.span, "invalid phi predecessor");
            continue;
          }
          require(n.operands[p].type == result);
          value(n.operands[p], predecessor,
                f.blocks[predecessor].instructions.size(), n.span);
        }
        break;
      }
      default:
        fail(n.span, "unknown instruction");
        break;
      }
    }
    const auto &exit = block.exit;
    if (exit.kind == Exit::Branch || exit.kind == Exit::Return) {
      value(exit.value, static_cast<int>(b), block.instructions.size(), {});
      if (exit.kind == Exit::Branch &&
          (exit.value.type != Type::Bool || exit.value.access != Access::Owned))
        fail({}, "branch requires bool");
      if (exit.kind == Exit::Return &&
          (f.result == Type::Never || exit.value.type != f.result ||
           exit.value.access != Access::Owned))
        fail({}, "return type does not match function");
    }
  }
  return valid;
}
} // namespace
bool verify(const Program &program, Diagnostics &diagnostics) {
  if (!program.types) {
    diagnostics.error("internal", {}, "CFG has no owned type store");
    return false;
  }
  bool valid = true;
  std::set<std::uint32_t> seen;
  std::function<void(Type, std::set<std::uint32_t>)> type =
      [&](Type current, std::set<std::uint32_t> owned) {
        auto invalid = [&](std::string message) {
          diagnostics.error("internal", {}, "invalid CFG type: " + message);
          valid = false;
        };
        if (!program.types->contains(current)) {
          invalid("unresolved type");
          return;
        }
        if (owned.contains(current.index())) {
          invalid("recursive by-value layout");
          return;
        }
        if (!seen.insert(current.index()).second)
          return;
        if (program.types->isView(current)) {
          const auto &view = program.types->view(current);
          if (view.mode != ParameterMode::Read &&
              view.mode != ParameterMode::Mut)
            invalid("invalid view access");
          type(view.payload, {});
        } else if (program.types->isProduct(current)) {
          owned.insert(current.index());
          const auto &product = program.types->product(current);
          for (const auto &field : product.fields) {
            type(field.type, owned);
            if (product.copyRequested && !program.types->isCopy(field.type))
              invalid("non-Copy field in Copy product");
          }
          if (product.hasDestructor) {
            if (product.copyRequested)
              invalid("Copy product has a user destructor");
            if (product.destructor < 0 ||
                static_cast<std::size_t>(product.destructor) >=
                    program.functions.size())
              invalid("invalid user destructor");
            else {
              const auto &destructor = program.functions[product.destructor];
              if (destructor.result != Type::Unit ||
                  destructor.parameters != 1 || destructor.locals.empty() ||
                  destructor.locals[0].type != current ||
                  destructor.locals[0].mode != ParameterMode::Mut)
                invalid("invalid user destructor signature");
            }
          }
        }
      };
  for (const auto &f : program.functions) {
    type(f.result, {});
    for (const auto &local : f.locals)
      type(local.type, {});
    for (const auto &block : f.blocks)
      for (const auto &instruction : block.instructions)
        type(instruction.result.type, {});
  }
  if (!valid)
    return false;
  bool entry = false;
  std::unordered_set<std::string> names;
  for (const auto &f : program.functions) {
    if (!names.insert(f.name).second) {
      diagnostics.error("internal", {}, "duplicate CFG function");
      valid = false;
    }
    if (f.name == "main")
      entry = f.parameters == 0 && f.result == Type::I32;
    valid = function(f, program, diagnostics) && valid;
  }
  if (!entry) {
    diagnostics.error("internal", {}, "invalid or absent CFG entry function");
    valid = false;
  }
  return valid;
}
} // namespace mettle::ir
