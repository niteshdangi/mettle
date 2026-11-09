#include "semantics/checker.h"
#include "support/limits.h"
#include <algorithm>
#include <charconv>
#include <functional>
#include <limits>
#include <map>
#include <optional>
#include <set>

namespace mettle {
void Checker::exhaustiveness() {
  using Row = std::vector<const Pattern *>;
  using Matrix = std::vector<Row>;
  struct Constructor {
    NumericLiteral key;
    std::vector<std::uint32_t> fields;
    std::vector<Type> types;
  };
  std::size_t steps = 0;
  auto wildcard = [](const Pattern *pattern) {
    return !pattern || pattern->kind == PatternKind::Wildcard ||
           pattern->kind == PatternKind::Binding;
  };
  auto literal = [&](const Pattern &pattern) {
    const auto &checkedPattern = facts(pattern);
    return checkedPattern.numeric ? *checkedPattern.numeric
                                  : integerLiteral(checkedPattern.number);
  };
  std::function<bool(Matrix, Row, std::vector<Type>)> useful;
  useful = [&](Matrix matrix, Row query, std::vector<Type> types) -> bool {
    if (++steps > limits::cleanupPlaces)
      throw std::length_error("pattern exhaustiveness limit exceeded");
    if (types.empty())
      return matrix.empty();
    Matrix expanded;
    std::function<void(Row)> expand = [&](Row row) {
      if (row[0] && row[0]->kind == PatternKind::At) {
        row[0] = &row[0]->children[0];
        expand(std::move(row));
        return;
      }
      if (row[0] && row[0]->kind == PatternKind::Or) {
        auto alternatives = row[0];
        for (const auto &alternative : alternatives->children) {
          row[0] = &alternative;
          expand(row);
        }
      } else
        expanded.push_back(std::move(row));
    };
    for (auto row : matrix)
      expand(std::move(row));
    matrix = std::move(expanded);
    while (query[0] && query[0]->kind == PatternKind::At)
      query[0] = &query[0]->children[0];
    if (query[0] && query[0]->kind == PatternKind::Or) {
      auto alternatives = query[0];
      for (const auto &alternative : alternatives->children) {
        query[0] = &alternative;
        if (useful(matrix, query, types))
          return true;
      }
      return false;
    }
    Type type = types[0];
    if (checked.types->uninhabited(type))
      return false;
    std::vector<Constructor> constructors;
    bool scalarColumn = false;
    if (checked.types->isSum(type)) {
      const auto &sum = checked.types->product(type);
      for (std::size_t variant = 0; variant < sum.variants.size(); ++variant) {
        Constructor constructor{
            integerLiteral(static_cast<std::int64_t>(variant)),
            sum.variants[variant].fields,
            {}};
        for (auto field : constructor.fields)
          constructor.types.push_back(sum.fields[field].type);
        constructors.push_back(std::move(constructor));
      }
    } else if (checked.types->isProduct(type)) {
      Constructor constructor{{}, {}, {}};
      const auto &product = checked.types->product(type);
      for (std::size_t field = 0; field < product.fields.size(); ++field) {
        constructor.fields.push_back(static_cast<std::uint32_t>(field));
        constructor.types.push_back(product.fields[field].type);
      }
      constructors.push_back(std::move(constructor));
    } else if (type == Type::Bool)
      constructors = {{integerLiteral(0), {}, {}}, {integerLiteral(1), {}, {}}};
    else if (type == Type::Unit)
      constructors = {{{}, {}, {}}};
    else {
      scalarColumn = true;
      auto less = [](const NumericLiteral &a, const NumericLiteral &b) {
        return compareIntegers(a, b) < 0;
      };
      auto maximum = type == Type::Char ? integerLiteral(0x10ffff)
                     : isInteger(type)  ? integerMaximum(type)
                                        : integerLiteral(0);
      std::set<NumericLiteral, decltype(less)> boundaries(less);
      boundaries.insert(isInteger(type) ? integerMinimum(type)
                                        : integerLiteral(0));
      auto successor = [&](NumericLiteral value) {
        if (compareIntegers(value, maximum) < 0)
          boundaries.insert(evaluateIntegerConstant(
              "+", type == Type::Char ? Type::U32 : type, value,
              integerLiteral(1)));
      };
      if (type == Type::Char) {
        boundaries.insert(integerLiteral(0xe000));
      }
      auto partition = [&](const Pattern *pattern) {
        if (wildcard(pattern))
          return;
        boundaries.insert(literal(*pattern));
        if (pattern->kind != PatternKind::Range)
          successor(literal(*pattern));
        else if (pattern->inclusive)
          successor(literal(pattern->children[0]));
        else
          boundaries.insert(literal(pattern->children[0]));
      };
      // Only boundaries inside the query's range can yield constructors that
      // the query specializes to; rows wholly outside it cannot split them.
      std::optional<NumericLiteral> low;
      std::optional<NumericLiteral> high; // inclusive
      if (!wildcard(query[0])) {
        low = literal(*query[0]);
        if (query[0]->kind != PatternKind::Range)
          high = low;
        else if (query[0]->inclusive)
          high = literal(query[0]->children[0]);
        else {
          auto end = literal(query[0]->children[0]);
          if (compareIntegers(end, *low) <= 0)
            return false;
          high = evaluateIntegerConstant("-",
                                         type == Type::Char ? Type::U32 : type,
                                         end, integerLiteral(1));
        }
      }
      auto overlaps = [&](const Pattern *pattern) {
        if (!low || wildcard(pattern))
          return true;
        auto first = literal(*pattern);
        if (compareIntegers(first, *high) > 0)
          return false;
        if (pattern->kind != PatternKind::Range)
          return compareIntegers(first, *low) >= 0;
        auto last = literal(pattern->children[0]);
        auto order = compareIntegers(last, *low);
        return pattern->inclusive ? order >= 0 : order > 0;
      };
      for (const auto &row : matrix)
        if (overlaps(row[0]))
          partition(row[0]);
      partition(query[0]);
      for (auto boundary : boundaries)
        if (compareIntegers(boundary, maximum) <= 0 &&
            (!low || (compareIntegers(boundary, *low) >= 0 &&
                      compareIntegers(boundary, *high) <= 0)) &&
            (type != Type::Char || !(boundary.magnitude[0] >= 0xd800 &&
                                     boundary.magnitude[0] < 0xe000)))
          constructors.push_back({boundary, {}, {}});
    }
    auto specialize =
        [&](const Row &row,
            const Constructor &constructor) -> std::optional<Row> {
      auto pattern = row[0];
      Row result(constructor.fields.size(), nullptr);
      if (!wildcard(pattern)) {
        if (pattern->kind == PatternKind::Range) {
          auto lower = literal(*pattern);
          auto upper = literal(pattern->children[0]);
          auto end = compareIntegers(constructor.key, upper);
          if (compareIntegers(constructor.key, lower) < 0 ||
              (pattern->inclusive ? end > 0 : end >= 0))
            return std::nullopt;
        } else if (pattern->kind == PatternKind::Literal) {
          if (literal(*pattern) != constructor.key)
            return std::nullopt;
        } else {
          const auto &checkedPattern = facts(*pattern);
          if (checkedPattern.variant >= 0 &&
              integerLiteral(checkedPattern.variant) != constructor.key)
            return std::nullopt;
          for (std::size_t child = 0; child < pattern->children.size();
               ++child) {
            if (pattern->children[child].kind == PatternKind::Rest)
              continue;
            auto field =
                std::find(constructor.fields.begin(), constructor.fields.end(),
                          checkedPattern.fields[child]);
            if (field == constructor.fields.end())
              return std::nullopt;
            result[field - constructor.fields.begin()] =
                &pattern->children[child];
          }
        }
      }
      result.insert(result.end(), row.begin() + 1, row.end());
      return result;
    };
    // Scalar constructors are sorted, disjoint boundaries: bucket each row by
    // binary search instead of specializing every row per constructor.
    std::vector<std::vector<std::size_t>> members;
    if (scalarColumn) {
      members.resize(constructors.size());
      auto before = [](const Constructor &constructor,
                       const NumericLiteral &value) {
        return compareIntegers(constructor.key, value) < 0;
      };
      for (std::size_t index = 0; index < matrix.size(); ++index) {
        auto pattern = matrix[index][0];
        auto first = constructors.begin();
        auto last = constructors.end();
        if (!wildcard(pattern)) {
          auto lower = literal(*pattern);
          first = std::lower_bound(constructors.begin(), constructors.end(),
                                   lower, before);
          if (pattern->kind != PatternKind::Range)
            last = first != constructors.end() && first->key == lower
                       ? first + 1
                       : first;
          else {
            auto upper = literal(pattern->children[0]);
            last = std::lower_bound(first, constructors.end(), upper, before);
            if (pattern->inclusive && last != constructors.end() &&
                last->key == upper)
              ++last;
          }
        }
        for (auto it = first; it < last; ++it)
          members[static_cast<std::size_t>(it - constructors.begin())]
              .push_back(index);
      }
    }
    for (std::size_t c = 0; c < constructors.size(); ++c) {
      const auto &constructor = constructors[c];
      auto wanted = specialize(query, constructor);
      if (!wanted)
        continue;
      Matrix specialized;
      if (scalarColumn)
        for (auto index : members[c])
          specialized.emplace_back(matrix[index].begin() + 1,
                                   matrix[index].end());
      else
        for (const auto &row : matrix)
          if (auto actual = specialize(row, constructor))
            specialized.push_back(std::move(*actual));
      auto childTypes = constructor.types;
      childTypes.insert(childTypes.end(), types.begin() + 1, types.end());
      if (useful(std::move(specialized), std::move(*wanted),
                 std::move(childTypes)))
        return true;
    }
    return false;
  };
  // Integer and char matches made only of literals, ranges and catch-alls
  // reduce to a merged interval set: each arm is O(log arms) instead of
  // rescanning every earlier arm.
  auto scalarMatch = [&](const Node &node, Type type) {
    if (!isInteger(type) && type != Type::Char)
      return false;
    for (std::size_t arm = 1; arm < node.children.size(); ++arm) {
      auto kind = node.children[arm]->patterns[0].kind;
      if (kind != PatternKind::Literal && kind != PatternKind::Range &&
          kind != PatternKind::Wildcard && kind != PatternKind::Binding)
        return false;
    }
    auto arithmetic = type == Type::Char ? Type::U32 : type;
    auto minimum = isInteger(type) ? integerMinimum(type) : integerLiteral(0);
    auto maximum =
        type == Type::Char ? integerLiteral(0x10ffff) : integerMaximum(type);
    auto less = [](const NumericLiteral &a, const NumericLiteral &b) {
      return compareIntegers(a, b) < 0;
    };
    std::map<NumericLiteral, NumericLiteral, decltype(less)> intervals(less);
    // `end` and `start` touch when end + 1 >= start.
    auto touches = [&](const NumericLiteral &end, const NumericLiteral &start) {
      return compareIntegers(end, start) >= 0 ||
             (compareIntegers(end, maximum) < 0 &&
              compareIntegers(evaluateIntegerConstant("+", arithmetic, end,
                                                      integerLiteral(1)),
                              start) >= 0);
    };
    auto covers = [&](const NumericLiteral &low, const NumericLiteral &high) {
      auto next = intervals.upper_bound(low);
      if (next == intervals.begin())
        return false;
      --next;
      return compareIntegers(next->second, high) >= 0;
    };
    auto insert = [&](NumericLiteral low, NumericLiteral high) {
      auto next = intervals.upper_bound(low);
      if (next != intervals.begin()) {
        auto previous = std::prev(next);
        if (touches(previous->second, low)) {
          low = previous->first;
          if (compareIntegers(previous->second, high) > 0)
            high = previous->second;
          intervals.erase(previous);
        }
      }
      next = intervals.lower_bound(low);
      while (next != intervals.end() && touches(high, next->first)) {
        if (compareIntegers(next->second, high) > 0)
          high = next->second;
        next = intervals.erase(next);
      }
      intervals.emplace(std::move(low), std::move(high));
    };
    if (type == Type::Char)
      insert(integerLiteral(0xd800), integerLiteral(0xdfff));
    for (std::size_t arm = 1; arm < node.children.size(); ++arm) {
      const auto &item = *node.children[arm];
      const auto &pattern = item.patterns[0];
      NumericLiteral low = minimum;
      NumericLiteral high = maximum;
      bool empty = false;
      if (!wildcard(&pattern)) {
        low = literal(pattern);
        if (pattern.kind == PatternKind::Literal)
          high = low;
        else if (pattern.inclusive)
          high = literal(pattern.children[0]);
        else {
          auto end = literal(pattern.children[0]);
          empty = compareIntegers(end, low) <= 0;
          if (!empty)
            high = evaluateIntegerConstant("-", arithmetic, end,
                                           integerLiteral(1));
        }
        empty = empty || compareIntegers(high, low) < 0;
      }
      if (empty || covers(low, high))
        error("type", item.span, "unreachable match arm");
      else if (!item.flag)
        insert(std::move(low), std::move(high));
    }
    if (!covers(minimum, maximum))
      error("type", node.span, "non-exhaustive match");
    return true;
  };
  Span subject{};
  try {
    for (auto [pattern, variable] : irrefutable) {
      steps = 0;
      subject = pattern->span;
      auto type = inference.value(variable);
      if (type != Type::Unknown && useful({{pattern}}, {nullptr}, {type}))
        error("type", pattern->span,
              "refutable pattern requires a diverging else");
    }
    for (auto [node, variable] : matches) {
      steps = 0;
      subject = node->span;
      Type type = inference.value(variable);
      if (type == Type::Unknown) {
        error("type", node->span, "cannot infer match input type");
        continue;
      }
      if (scalarMatch(*node, type))
        continue;
      Matrix covered;
      for (std::size_t arm = 1; arm < node->children.size(); ++arm) {
        const auto &item = *node->children[arm];
        Row query{&item.patterns[0]};
        if (!useful(covered, query, {type}))
          error("type", item.span, "unreachable match arm");
        else if (item.patterns[0].kind == PatternKind::Or) {
          auto alternatives = covered;
          std::function<void(const Pattern &)> check =
              [&](const Pattern &pattern) {
                if (pattern.kind == PatternKind::Or) {
                  for (const auto &child : pattern.children)
                    check(child);
                  return;
                }
                Row alternative{&pattern};
                if (!useful(alternatives, alternative, {type}))
                  error("type", pattern.span,
                        "unreachable or-pattern alternative");
                alternatives.push_back(std::move(alternative));
              };
          check(item.patterns[0]);
        }
        if (!item.flag)
          covered.push_back(std::move(query));
      }
      if (useful(covered, {nullptr}, {type}))
        error("type", node->span, "non-exhaustive match");
    }
  } catch (const std::length_error &exception) {
    error("limit", subject, exception.what());
  }
}
} // namespace mettle
