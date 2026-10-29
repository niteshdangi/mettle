#include "semantics/checker.h"
#include "support/limits.h"
#include <charconv>
#include <functional>
#include <limits>
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
    return facts(pattern).numeric.value_or(
        integerLiteral(facts(pattern).number));
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
      for (const auto &row : matrix)
        partition(row[0]);
      partition(query[0]);
      for (auto boundary : boundaries)
        if (compareIntegers(boundary, maximum) <= 0 &&
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
    for (const auto &constructor : constructors) {
      auto wanted = specialize(query, constructor);
      if (!wanted)
        continue;
      Matrix specialized;
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
  try {
    for (auto [pattern, variable] : irrefutable) {
      auto type = inference.value(variable);
      if (type != Type::Unknown && useful({{pattern}}, {nullptr}, {type}))
        error("type", pattern->span,
              "refutable pattern requires a diverging else");
    }
    for (auto [node, variable] : matches) {
      Type type = inference.value(variable);
      if (type == Type::Unknown) {
        error("type", node->span, "cannot infer match input type");
        continue;
      }
      Matrix covered;
      for (std::size_t arm = 1; arm < node->children.size(); ++arm) {
        const auto &item = *node->children[arm];
        Row query{&item.patterns[0]};
        if (!useful(covered, query, {type}))
          error("type", item.span, "unreachable match arm");
        if (!item.flag)
          covered.push_back(std::move(query));
      }
      if (useful(covered, {nullptr}, {type}))
        error("type", node->span, "non-exhaustive match");
    }
  } catch (const std::length_error &exception) {
    error("limit", {}, exception.what());
  }
}
} // namespace mettle
