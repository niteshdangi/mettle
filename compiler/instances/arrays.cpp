#include "instances/arrays.h"
#include "support/limits.h"
#include <algorithm>
#include <map>
#include <set>
#include <stdexcept>

namespace mettle::instances {
namespace {
void unrollLoops(ir::Function &function, const TypeStore &types) {
  for (std::size_t l = 0; l < function.arrayLoops.size(); ++l) {
    auto loop = function.arrayLoops[l];
    auto type = *projectedType(types, function.locals[loop.source.root].type,
                               loop.source.fields);
    auto count = types.product(type).fields.size();
    if (count && loop.blocks.size() >
                     (limits::cfgBlocks - function.blocks.size()) / count)
      throw std::length_error("generic array iteration CFG limit exceeded");
    std::set<int> declared;
    for (auto block : loop.blocks)
      for (const auto &instruction : function.blocks[block].instructions)
        if (instruction.op == ir::Op::Declare)
          declared.insert(instruction.place.root);
    if (count &&
        declared.size() > (limits::locals - function.locals.size()) / count)
      throw std::length_error("generic array iteration local limit exceeded");
    std::vector<std::map<int, int>> blocks(count);
    std::vector<int> created;
    for (std::size_t iteration = 0; iteration < count; ++iteration)
      for (auto source : loop.blocks) {
        auto id = static_cast<int>(function.blocks.size());
        function.blocks.emplace_back();
        blocks[iteration].emplace(source, id);
        created.push_back(id);
      }
    for (std::size_t iteration = 0; iteration < count; ++iteration) {
      std::map<int, int> locals, values;
      for (auto source : declared) {
        locals.emplace(source, static_cast<int>(function.locals.size()));
        auto local = function.locals[source];
        function.locals.push_back(std::move(local));
      }
      for (auto block : loop.blocks)
        for (const auto &instruction : function.blocks[block].instructions)
          if (instruction.result.id >= 0)
            values.emplace(instruction.result.id, function.values++);
      ir::Value index{function.values++, Type::I32};
      values[loop.index.id] = index.id;
      auto remapValue = [&](ir::Value &value) {
        if (auto found = values.find(value.id); found != values.end())
          value.id = found->second;
      };
      auto remapPlace = [&](Place &place) {
        if (auto found = locals.find(place.root); found != locals.end())
          place.root = found->second;
      };
      auto target = [&](int block) {
        if (block == loop.step)
          return iteration + 1 == count ? loop.done
                                        : blocks[iteration + 1].at(loop.body);
        if (auto found = blocks[iteration].find(block);
            found != blocks[iteration].end())
          return found->second;
        return block;
      };
      for (auto source : loop.blocks) {
        auto copy = function.blocks[source];
        for (auto &instruction : copy.instructions) {
          if (instruction.result.id == loop.element) {
            instruction.op = loop.mode == ParameterMode::Take ? ir::Op::Move
                             : loop.mode == ParameterMode::Mut
                                 ? ir::Op::ViewMut
                                 : ir::Op::ViewRead;
            instruction.place.fields.push_back(
                Projection::field(static_cast<std::uint32_t>(iteration)));
            instruction.operands.clear();
          }
          remapValue(instruction.result);
          for (auto &operand : instruction.operands)
            remapValue(operand);
          remapValue(instruction.target);
          remapPlace(instruction.place);
          for (auto &predecessor : instruction.predecessors)
            predecessor = target(predecessor);
        }
        remapValue(copy.exit.value);
        if (copy.exit.kind == ir::Exit::Jump ||
            copy.exit.kind == ir::Exit::Branch)
          copy.exit.first = target(copy.exit.first);
        if (copy.exit.kind == ir::Exit::Branch)
          copy.exit.second = target(copy.exit.second);
        if (source == loop.body)
          copy.instructions.insert(copy.instructions.begin(),
                                   {ir::Op::Constant,
                                    index,
                                    {},
                                    {},
                                    "",
                                    {-1, {}},
                                    -1,
                                    static_cast<std::int32_t>(iteration),
                                    {}});
        function.blocks[blocks[iteration].at(source)] = std::move(copy);
      }
    }
    function.blocks[loop.header].exit = {
        ir::Exit::Jump, {}, count ? blocks[0].at(loop.body) : loop.done};
    function.blocks[loop.step].instructions.clear();
    function.blocks[loop.step].exit = {ir::Exit::Unreachable};
    for (auto source : loop.blocks) {
      function.blocks[source].instructions.clear();
      function.blocks[source].exit = {ir::Exit::Unreachable};
    }
    for (std::size_t outer = l + 1; outer < function.arrayLoops.size();
         ++outer) {
      auto &region = function.arrayLoops[outer].blocks;
      if (std::find(region.begin(), region.end(), loop.header) != region.end())
        region.insert(region.end(), created.begin(), created.end());
    }
  }
  function.arrayLoops.clear();
}
void reachableBlocks(ir::Function &function) {
  if (function.blocks.empty())
    return;
  std::vector<bool> reachable(function.blocks.size());
  std::vector<int> work{0};
  while (!work.empty()) {
    auto block = work.back();
    work.pop_back();
    if (reachable[block])
      continue;
    reachable[block] = true;
    auto exit = function.blocks[block].exit;
    if (exit.kind == ir::Exit::Jump || exit.kind == ir::Exit::Branch)
      work.push_back(exit.first);
    if (exit.kind == ir::Exit::Branch)
      work.push_back(exit.second);
  }
  std::vector<int> mapping(function.blocks.size(), -1);
  int next = 0;
  for (std::size_t i = 0; i < reachable.size(); ++i)
    if (reachable[i])
      mapping[i] = next++;
  std::vector<ir::Block> blocks;
  for (std::size_t i = 0; i < function.blocks.size(); ++i) {
    if (!reachable[i])
      continue;
    auto block = std::move(function.blocks[i]);
    for (auto &instruction : block.instructions)
      if (instruction.op == ir::Op::Phi) {
        std::vector<int> predecessors;
        std::vector<ir::Value> operands;
        for (std::size_t p = 0; p < instruction.predecessors.size(); ++p) {
          auto predecessor = instruction.predecessors[p];
          const auto &exit = function.blocks[predecessor].exit;
          auto edge =
              (exit.kind == ir::Exit::Jump || exit.kind == ir::Exit::Branch) &&
              exit.first == static_cast<int>(i);
          edge |= exit.kind == ir::Exit::Branch &&
                  exit.second == static_cast<int>(i);
          if (reachable[predecessor] && edge) {
            predecessors.push_back(mapping[predecessor]);
            operands.push_back(instruction.operands[p]);
          }
        }
        instruction.predecessors = std::move(predecessors);
        instruction.operands = std::move(operands);
      }
    if (block.exit.kind == ir::Exit::Jump ||
        block.exit.kind == ir::Exit::Branch)
      block.exit.first = mapping[block.exit.first];
    if (block.exit.kind == ir::Exit::Branch)
      block.exit.second = mapping[block.exit.second];
    blocks.push_back(std::move(block));
  }
  function.blocks = std::move(blocks);
  std::map<int, int> values;
  for (const auto &block : function.blocks)
    for (const auto &instruction : block.instructions)
      if (instruction.result.id >= 0)
        values.emplace(instruction.result.id, static_cast<int>(values.size()));
  auto remap = [&](ir::Value &value) {
    if (value.id >= 0)
      value.id = values.at(value.id);
  };
  for (auto &block : function.blocks) {
    for (auto &instruction : block.instructions) {
      remap(instruction.result);
      for (auto &operand : instruction.operands)
        remap(operand);
      remap(instruction.target);
    }
    remap(block.exit.value);
  }
  function.values = static_cast<int>(values.size());
}
} // namespace
void expandArrays(ir::Function &function, const TypeStore &types) {
  bool expanded = !function.arrayLoops.empty();
  unrollLoops(function, types);
  if (expanded)
    reachableBlocks(function);
  auto block = [&] {
    if (function.blocks.size() >= limits::cfgBlocks)
      throw std::length_error("generic array CFG expansion limit exceeded");
    auto result = static_cast<int>(function.blocks.size());
    function.blocks.emplace_back();
    return result;
  };
  auto append = [&](int target, ir::Instruction instruction, Type type) {
    instruction.result = {function.values++, type};
    auto result = instruction.result;
    function.blocks[target].instructions.push_back(std::move(instruction));
    return result;
  };
  for (std::size_t b = 0; b < function.blocks.size(); ++b)
    for (std::size_t i = 0; i < function.blocks[b].instructions.size(); ++i) {
      auto instruction = function.blocks[b].instructions[i];
      if (instruction.op == ir::Op::ArrayRepeat) {
        auto count = types.product(instruction.result.type).fields.size();
        instruction.op = ir::Op::Construct;
        auto element = instruction.operands.at(0);
        instruction.operands.assign(count, element);
        function.blocks[b].instructions[i] = std::move(instruction);
        continue;
      }
      if (instruction.op != ir::Op::ArrayBorrowRead &&
          instruction.op != ir::Op::ArrayBorrowMut)
        continue;
      expanded = true;
      auto source =
          *projectedType(types, function.locals[instruction.place.root].type,
                         instruction.place.fields);
      auto count = types.product(source).fields.size();
      auto originalExit = function.blocks[b].exit;
      std::vector<ir::Instruction> remaining(
          function.blocks[b].instructions.begin() +
              static_cast<std::ptrdiff_t>(i + 1),
          function.blocks[b].instructions.end());
      function.blocks[b].instructions.resize(i);
      int done = -1;
      if (count) {
        done = block();
        function.blocks[done].instructions = std::move(remaining);
        function.blocks[done].exit = originalExit;
        for (auto &candidate : function.blocks)
          for (auto &operation : candidate.instructions)
            if (operation.op == ir::Op::Phi)
              for (auto &predecessor : operation.predecessors)
                if (predecessor == static_cast<int>(b))
                  predecessor = done;
      }
      int current = static_cast<int>(b);
      std::vector<ir::Value> values;
      std::vector<int> predecessors;
      for (std::size_t field = 0; field < count; ++field) {
        ir::Instruction expected{ir::Op::Constant,
                                 {},
                                 {},
                                 {},
                                 "",
                                 {-1, {}},
                                 -1,
                                 static_cast<std::int32_t>(field),
                                 instruction.span};
        auto number = append(current, std::move(expected),
                             instruction.operands.at(0).type);
        auto test = append(current,
                           {ir::Op::Binary,
                            {},
                            {instruction.operands.at(0), number},
                            {},
                            "==",
                            {-1, {}},
                            -1,
                            0,
                            instruction.span},
                           Type::Bool);
        auto yes = block(), no = block();
        function.blocks[current].exit = {ir::Exit::Branch, test, yes, no};
        auto place = instruction.place;
        place.fields.push_back(
            Projection::field(static_cast<std::uint32_t>(field)));
        values.push_back(
            append(yes,
                   {instruction.op == ir::Op::ArrayBorrowRead ? ir::Op::ViewRead
                                                              : ir::Op::ViewMut,
                    {},
                    {},
                    {},
                    "",
                    place,
                    -1,
                    0,
                    instruction.span},
                   instruction.result.type));
        predecessors.push_back(yes);
        function.blocks[yes].exit = {ir::Exit::Jump, {}, done};
        current = no;
      }
      append(current,
             {ir::Op::Panic, {}, {}, {}, "", {-1, {}}, -1, 2, instruction.span},
             Type::Never);
      function.blocks[current].exit = {ir::Exit::Unreachable};
      if (done >= 0) {
        ir::Instruction phi{ir::Op::Phi,
                            instruction.result,
                            std::move(values),
                            std::move(predecessors),
                            "",
                            {-1, {}},
                            -1,
                            0,
                            instruction.span};
        function.blocks[done].instructions.insert(
            function.blocks[done].instructions.begin(), std::move(phi));
      }
      break;
    }
  if (expanded)
    reachableBlocks(function);
}
} // namespace mettle::instances
