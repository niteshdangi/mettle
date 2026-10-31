#pragma once

#include "syntax/token.h"
#include <memory>
#include <optional>
#include <utility>

namespace mettle {
struct Node;
class NodeOwner {
public:
  NodeOwner();
  NodeOwner(std::unique_ptr<Node> value);
  NodeOwner(NodeOwner &&) noexcept;
  NodeOwner &operator=(NodeOwner &&) noexcept;
  ~NodeOwner();
  // A non-owning reference, so semantic elaborations can share syntax nodes
  // that remain owned by the parsed tree.
  static NodeOwner borrow(Node &node);
  bool owns() const { return owning; }
  // Hands over an owned node, leaving this reference empty.
  std::unique_ptr<Node> release() { return std::move(value); }
  Node *get() { return value.get(); }
  const Node *get() const { return value.get(); }
  Node &operator*() { return *value; }
  const Node &operator*() const { return *value; }
  Node *operator->() { return value.get(); }
  const Node *operator->() const { return value.get(); }

private:
  std::unique_ptr<Node> value;
  bool owning = true;
};
enum class Kind {
  Integer,
  Boolean,
  Unit,
  Name,
  Group,
  Unary,
  Binary,
  Call,
  Block,
  If,
  Binding,
  Assign,
  Return,
  While,
  Loop,
  Break,
  Continue,
  Field,
  None,
  Variant,
  Match,
  Arm,
  Throw,
  Try,
  Capture,
  Tuple,
  Array,
  Index,
  Range,
  For,
  Coalesce,
  Character,
  Text,
  Closure,
  Floating,
  Cast,
  Unsafe,
  Assembly,
  FeatureTest
};
struct CallableTypeSyntax;
enum class TypeForm {
  Named,
  Optional,
  Outcome,
  Tuple,
  Array,
  Callable,
  Erased,
  Opaque,
  Projection,
  Slice,
  Pointer,
  Pinned,
  Owner
};
enum class OwnerKind {
  Heap,
  Shared,
  LocalShared,
  Weak,
  LocalWeak
};
struct TypeSyntax;
struct GenericArgument {
  std::shared_ptr<const TypeSyntax> type{};
  std::shared_ptr<const Node> value{};
  std::string region{};
  Span span{};
  std::string binding{};
};
struct TypeSyntax {
  std::string name, view;
  std::vector<std::string> sources, regions;
  std::shared_ptr<const TypeSyntax> nested{};
  TypeForm form = TypeForm::Named;
  OwnerKind ownerKind = OwnerKind::Heap;
  std::vector<TypeSyntax> elements{};
  std::uint32_t count = 0;
  std::shared_ptr<const Node> countExpression{};
  std::vector<GenericArgument> arguments{};
  std::shared_ptr<const CallableTypeSyntax> callable{};
  std::vector<std::string> binders{};
  bool empty() const {
    return name.empty() && !nested && form == TypeForm::Named;
  }
};
struct CallableParameterSyntax {
  TypeSyntax annotation;
  std::string mode{}, name{};
};
struct CallableTypeSyntax {
  std::vector<CallableParameterSyntax> parameters;
  TypeSyntax result, error;
  std::string mode{};
  std::vector<std::string> regions{};
  bool unsafeCall = false;
  std::string abi{};
  bool variadic = false;
};
enum class GenericParameterKind { Type, Const, Region };
struct GenericParameter {
  GenericParameterKind kind = GenericParameterKind::Type;
  std::string name;
  Span span;
  std::vector<TypeSyntax> bounds{};
  TypeSyntax annotation{}, defaultType{};
  std::shared_ptr<const Node> defaultValue{};
};
struct GenericConstraint {
  TypeSyntax subject;
  std::vector<TypeSyntax> bounds{};
  std::optional<TypeSyntax> equality{};
  Span span{};
  bool region = false;
};
enum class PatternKind {
  Wildcard,
  Binding,
  Literal,
  Variant,
  Product,
  Or,
  Tuple,
  Array,
  Range,
  At,
  Rest
};
struct Pattern {
  PatternKind kind = PatternKind::Wildcard;
  Span span;
  std::string text{};
  std::string field{};
  std::vector<Pattern> children{};
  bool inclusive = false;
  bool rest = false;
  TokenKind literalKind = TokenKind::Integer;
};
struct ClosureParameter {
  std::string name;
  TypeSyntax annotation;
  Span span;
  std::string mode{};
  std::optional<Pattern> pattern{};
};
struct AssemblySyntax {
  std::string variant;
  std::vector<std::string> templates, options, clobberAbis;
  struct Operand {
    std::string mode, name, reg;
    bool explicitRegister = false, discard = false;
    int input = -1, output = -1;
    Span span{};
  };
  std::vector<Operand> operands;
};
struct Node {
  Kind kind;
  Span span;
  std::string text;
  std::string name;
  std::string label;
  TypeSyntax annotation;
  std::vector<NodeOwner> children;
  bool flag = false;
  bool semicolon = false;
  unsigned depth = 1;
  std::vector<Pattern> patterns{};
  std::vector<ClosureParameter> parameters{};
  TypeSyntax error{};
  std::vector<GenericArgument> genericArguments{};
  std::vector<GenericArgument> ownerGenericArguments{};
  std::optional<AssemblySyntax> assembly{};
};
inline NodeOwner::NodeOwner() = default;
inline NodeOwner::NodeOwner(std::unique_ptr<Node> node)
    : value(std::move(node)) {}
inline NodeOwner::NodeOwner(NodeOwner &&other) noexcept
    : value(std::move(other.value)), owning(other.owning) {}
inline NodeOwner &NodeOwner::operator=(NodeOwner &&other) noexcept {
  if (this != &other) {
    if (!owning)
      value.release();
    value = std::move(other.value);
    owning = other.owning;
  }
  return *this;
}
inline NodeOwner::~NodeOwner() {
  if (!owning)
    value.release();
}
inline NodeOwner NodeOwner::borrow(Node &node) {
  NodeOwner result;
  result.value.reset(&node);
  result.owning = false;
  return result;
}
struct VisibilitySyntax {
  bool publicItem = false;
  std::vector<std::string> restriction;
  Span span;
};
struct Attribute {
  std::string name;
  std::vector<Token> arguments;
  Span span;
  bool parenthesized = false;
};
struct ItemSyntax {
  std::vector<std::string> scope;
  VisibilitySyntax visibility{};
  std::vector<Attribute> attributes{};
};
struct Parameter {
  std::string name;
  TypeSyntax annotation;
  Span span;
  std::string mode{};
  NodeOwner defaultValue{};
  VisibilitySyntax visibility{};
  std::optional<Pattern> pattern{};
  std::vector<Attribute> attributes{};
  // `format Message`: the argument is a recipe that cannot escape the call.
  bool format = false;
};
struct Function {
  std::string name;
  TypeSyntax annotation;
  Span span;
  std::vector<Parameter> parameters;
  NodeOwner body;
  std::string owner, receiver;
  bool destructor = false;
  std::vector<std::string> regions;
  ItemSyntax item{};
  bool constructor = false;
  TypeSyntax error{};
  std::vector<GenericParameter> genericParameters{};
  std::vector<GenericConstraint> constraints{};
  std::size_t implicitGenericParameters = 0;
  std::string interfaceOwner{};
  int implementation = -1;
  bool unsafeFunction = false;
  bool constFunction = false;
  bool asynchronous = false;
  TypeSyntax asyncOutput{}, asyncError{};
  std::string asyncFuture{};
  std::string abi{};
  bool foreignDeclaration = false;
  bool variadic = false;
  bool explicitReceiver = false;
  std::string variadicCursor{};
  Span variadicSpan{};
};
struct Module {
  std::vector<Token> tokens;
  // Spans of text-literal expressions; the loader uses them to mount the
  // library that defines Text.
  std::vector<Span> textLiterals;
  std::vector<Function> functions;
  struct Static {
    std::string name;
    TypeSyntax annotation;
    NodeOwner initializer;
    Span span;
    ItemSyntax item{};
    bool mutableBinding = false;
    bool foreignDeclaration = false;
    // `const` items share static storage; the flag selects value semantics.
    bool constant = false;
  };
  std::vector<Static> statics;
  std::vector<NodeOwner> globalAssembly{};
  struct Associated {
    std::string name;
    Span span;
    VisibilitySyntax visibility{};
    bool constant = false;
    bool asyncFuture = false;
    bool asyncFutureOutputInferred = false;
    TypeSyntax annotation{}, value{};
    std::shared_ptr<const Node> constantValue{};
    std::vector<GenericParameter> genericParameters{};
    std::vector<TypeSyntax> bounds{};
    std::vector<GenericConstraint> constraints{};
  };
  struct Product {
    std::string name;
    Span span;
    bool copyRequested = false;
    std::vector<Parameter> fields;
    std::vector<std::string> regions;
    std::vector<Function> methods;
    bool hasDestructor = false;
    struct Variant {
      std::string name;
      std::vector<Parameter> fields;
      Span span;
      std::shared_ptr<const Node> discriminant{};
      std::vector<Attribute> attributes{};
    };
    bool enumeration = false;
    bool unionType = false;
    std::vector<Variant> variants;
    ItemSyntax item{};
    std::vector<GenericParameter> genericParameters{};
    std::vector<GenericConstraint> constraints{};
    std::vector<TypeSyntax> interfaces{};
    std::vector<Associated> associated{};
    std::vector<std::pair<std::string, Span>> deriveRequests{};
  };
  std::vector<Product> products;
  struct Alias {
    std::string name;
    TypeSyntax target;
    Span span;
    ItemSyntax item{};
    std::vector<GenericParameter> genericParameters{};
    std::vector<GenericConstraint> constraints{};
  };
  std::vector<Alias> aliases;
  struct Interface {
    std::string name;
    Span span;
    ItemSyntax item{};
    std::vector<GenericParameter> genericParameters{};
    std::vector<GenericConstraint> constraints{};
    std::vector<TypeSyntax> superinterfaces{};
    std::vector<Associated> associated{};
    std::vector<Function> methods{};
  };
  struct Implementation {
    TypeSyntax target, interface;
    Span span;
    ItemSyntax item{};
    std::vector<GenericParameter> genericParameters{};
    std::vector<GenericConstraint> constraints{};
    std::vector<Associated> associated{};
    std::vector<Function> methods{};
    std::vector<std::size_t> methodFunctions{};
    bool shorthand = false;
    bool negative = false;
    bool unsafeImplementation = false;
  };
  std::vector<Interface> interfaces{};
  std::vector<Implementation> implementations{};
  struct ModuleDeclaration {
    std::string name;
    Span span;
    bool external = false;
    ItemSyntax item;
  };
  struct Import {
    struct Name {
      std::string name, alias;
      Span span;
    };
    std::vector<std::string> path;
    std::vector<Name> names;
    std::string alias;
    bool glob = false;
    // Loader-synthesized dependency alias; an explicit import of the same item
    // in its scope is not a duplicate binding.
    bool synthesized = false;
    Span span;
    ItemSyntax item;
  };
  std::vector<ModuleDeclaration> modules;
  std::vector<Import> imports;
  // Names the loader makes visible, below every explicit and glob binding, in
  // each module outside `libraryRoots`. Empty when no library supplies them.
  struct Prelude {
    std::vector<std::vector<std::string>> names;
    std::vector<std::string> libraryRoots;
  } prelude;
  // Functions annotated `@test` or `@bench` in the selected package, collected
  // by attribute expansion for the test/benchmark harness. `path` is the
  // enclosing modules followed by the function name.
  struct TestFunction {
    std::vector<std::string> path;
    Span span;
    bool bench = false, ignored = false, shouldPanic = false;
    // The function declares a typed failure (`throws`); returning it fails.
    bool fallible = false;
    std::string ignoreReason, panicMessage;
  };
  std::vector<TestFunction> tests;
};
std::optional<bool> booleanLiteral(const Node &node);
// The `::`-joined spelling of a plain Name or Field chain (`a.b.c`), or
// nullopt when a link carries generic arguments, an optional access or any
// other form. The parser keeps `a.b` as Field nodes because whether it names a
// module, type or value needs name resolution; this is the syntactic view a
// resolver uses to retry a chain as a qualified path.
std::optional<std::string> dottedPath(const Node &node);
// Labels of the calls that build a format recipe (see `formatRecipe`).
inline constexpr std::string_view formatRecipeLabel = "f-string";
inline constexpr std::string_view formatInternalLabel = "f-string-internal";
// The recipe call for interpolations `holes`: `pieces` holds the literal text
// before each hole plus the tail, as text-literal nodes. It lowers to the
// core::fmt constructors, which only marked calls may use outside unsafe code.
std::unique_ptr<Node> formatRecipe(Span span,
                                   std::vector<std::unique_ptr<Node>> holes,
                                   std::vector<std::unique_ptr<Node>> pieces);
bool isStatement(Kind kind);
} // namespace mettle
