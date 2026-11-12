#include "ir/codec.h"
#include "ir/verify.h"
#include "metadata/type_graph.h"
#include <algorithm>
#include <iostream>
#include <map>
#include <stdexcept>

namespace {
using namespace mettle;
using namespace mettle::ir;
using metadata::SymbolKind;
void require(bool condition, const char *message) {
  if (!condition)
    throw std::runtime_error(message);
}
Function constantFunction(std::string name, int number) {
  Instruction constant{Op::Constant, {0, Type::I32}, {},       {}, "", {},
                       -1,           number,         {2, 8, 7}};
  return {std::move(name),
          Type::I32,
          0,
          {},
          {{{constant}, {Exit::Return, {0, Type::I32}}}},
          1};
}
std::string prefix(SymbolKind kind) {
  switch (kind) {
  case SymbolKind::Function:
    return "fn/";
  case SymbolKind::Static:
    return "static/";
  case SymbolKind::Closure:
    return "closure/";
  case SymbolKind::Interface:
    return "interface/";
  case SymbolKind::Package:
    return "package/";
  }
  throw std::runtime_error("unknown symbol domain");
}
std::optional<std::string> symbolName(SymbolKind kind, std::uint32_t id) {
  return "core@revision/" + prefix(kind) + std::to_string(id);
}
constexpr std::array<std::uint32_t, 5> destinations{4, 2, 6, 3, 5};
std::optional<std::uint32_t> resolve(SymbolKind kind, std::string_view name) {
  auto stem = "core@revision/" + prefix(kind);
  if (!name.starts_with(stem))
    return std::nullopt;
  auto suffix = name.substr(stem.size());
  if (suffix == "99" && kind == SymbolKind::Function)
    return 0;
  if (suffix == "23" && kind == SymbolKind::Interface)
    return 91;
  for (std::uint32_t i = 0; i < 5; ++i)
    if (suffix == std::to_string(i)) {
      if (kind == SymbolKind::Function)
        return destinations[i];
      if (kind == SymbolKind::Static && i < 3)
        return (i + 2) % 3;
      if (kind == SymbolKind::Closure)
        return i + 3;
    }
  return std::nullopt;
}
struct Fixture {
  std::vector<std::uint8_t> irBytes, typeBytes;
  std::size_t typeRoots = 0;
};
Fixture encodeFixture(bool addressOnly = false) {
  auto types = std::make_shared<TypeStore>();
  auto parameter = types->declareParameter("identity.T", true);
  auto product = types->declareProduct("Pair", true);
  types->defineProduct(product, {{"first", Type::I32}, {"second", Type::I32}});
  ErasedType interface;
  interface.name = "Trait";
  interface.declaration = 23;
  auto bound = types->erasedType(interface);
  CallableType closureSignature;
  closureSignature.result = Type::I32;
  closureSignature.abiResult = Type::I32;
  closureSignature.function = 0;
  auto closure = types->closureType("$closure", {}, closureSignature);
  CallableType pointerSignature;
  pointerSignature.result = Type::I32;
  pointerSignature.abiResult = Type::I32;
  auto pointer = types->callableType(pointerSignature);
  Program p;
  p.types = types;
  p.requireEntry = false;
  p.target = targetFacts("x86_64-unknown-linux-gnu");
  p.functions = {constantFunction("api", 0), constantFunction("$default", 7),
                 constantFunction("$private", 9),
                 constantFunction("identity", 0),
                 constantFunction("$closure.body", 5)};
  auto &api = p.functions[0];
  api.locals = {{"pair", product, false, {}, ParameterMode::Value, 1}};
  api.scopes.push_back({0});
  api.blocks[0].instructions = {
      {Op::Load,
       {0, Type::I32},
       {},
       {},
       "",
       {0, {Projection::field(1)}},
       -1,
       0,
       {}},
      {Op::Call, {1, Type::I32}, {{0, Type::I32}}, {}, "", {}, 3, 0, {}},
      {Op::Call, {2, Type::I32}, {}, {}, "", {}, 1, 0, {}},
      {Op::Binary,
       {3, Type::I32},
       {{1, Type::I32}, {2, Type::I32}},
       {},
       "+",
       {},
       -1,
       0,
       {}}};
  api.blocks[0].instructions[1].typeArguments = {Type::I32};
  for (auto &instruction : api.blocks[0].instructions) {
    instruction.scope = 1;
    instruction.span = {2, 8, 7};
  }
  api.blocks[0].instructions.push_back(
      {Op::Constant, {4, Type::Bool}, {}, {}, "", {}, -1, 1, {}});
  api.blocks[0].exit = {Exit::Branch, {4, Type::Bool}, 1, 2};
  api.blocks.push_back({{}, {Exit::Jump, {}, 3}});
  api.blocks.push_back({{}, {Exit::Jump, {}, 3}});
  api.blocks.push_back({{{Op::Phi,
                          {5, Type::I32},
                          {{3, Type::I32}, {3, Type::I32}},
                          {1, 2},
                          "",
                          {},
                          -1,
                          0,
                          {}}},
                        {Exit::Return, {5, Type::I32}}});
  api.values = 6;
  api.inlineHint = InlineHint::Always;
  api.floatingPolicy = {true, false, true, false, true, false, true};
  api.targetFeatures = {"sse2"};
  api.span = {1, 12, 7};
  p.functions[1].blocks[0].instructions[0] = {
      Op::Call, {0, Type::I32}, {}, {}, "", {}, 2, 0, {}};
  p.functions[1].locals = {
      {"inactive", Type::I32, false, {}, ParameterMode::Value, -1},
      {"escaping", Type::I32, false, {}, ParameterMode::Value, -2}};
  auto &privateBody = p.functions[2];
  privateBody.locals = {{"COUNTER",
                         Type::I32,
                         false,
                         {},
                         ParameterMode::Value,
                         0,
                         0,
                         StorageDuration::Static,
                         0}};
  privateBody.blocks[0].instructions = {
      {Op::Load, {0, Type::I32}, {}, {}, "", {0, {}}, -1, 0, {}},
      {Op::Call, {1, Type::I32}, {}, {}, "", {}, 99, 0, {}},
      {Op::Binary,
       {2, Type::I32},
       {{0, Type::I32}, {1, Type::I32}},
       {},
       "+",
       {},
       -1,
       0,
       {}}};
  privateBody.values = 3;
  privateBody.blocks[0].exit.value = {2, Type::I32};
  auto &generic = p.functions[3];
  generic.result = parameter;
  generic.parameters = 1;
  generic.locals = {{"value", parameter, false, {}}};
  generic.genericParameters = {parameter};
  generic.genericResultSources = {0};
  generic.interfaceBounds = {{parameter, bound}};
  generic.unpinBounds = {parameter};
  generic.sizedBounds = {parameter};
  generic.genericEqualities = {{parameter, parameter}};
  generic.blocks[0].instructions = {
      {Op::Load, {0, parameter}, {}, {}, "", {0, {}}, -1, 0, {}}};
  generic.blocks[0].exit.value = {0, parameter};
  p.functionPackages.assign(p.functions.size(), "core@revision");
  p.closureFunctions = {4};
  StaticConstant scalar;
  scalar.type = Type::I32;
  scalar.scalar = integerLiteral(9);
  StaticConstant address;
  address.kind = StaticConstant::Kind::Address;
  address.type = types->pointerType(Type::I32, ParameterMode::Read);
  address.symbol = 0;
  address.byteOffset = 4;
  if (addressOnly) {
    address.kind = StaticConstant::Kind::Pointer;
    address.symbol = -1;
    address.byteOffset = 0;
    address.scalar = integerLiteral(16);
  }
  StaticConstant function;
  function.kind = StaticConstant::Kind::Function;
  function.type = pointer;
  function.symbol = 2;
  p.statics = {{"COUNTER", {}, {}, scalar.type, false, false, {}, scalar},
               {"COUNTER_PTR", {}, {}, address.type, false, false, {}, address},
               {"HELPER_PTR", {}, {}, pointer, false, false, {}, function}};
  p.staticPackages.assign(p.statics.size(), "core@revision");
  Assembly global;
  global.variant = AssemblyVariant::Global;
  global.templates = {".quad {0}", ".quad {1}"};
  AssemblyOperand functionSymbol;
  functionSymbol.mode = AssemblyMode::Sym;
  functionSymbol.symbol = 2;
  functionSymbol.symbolArguments = {parameter};
  AssemblyOperand staticSymbol = functionSymbol;
  staticSymbol.symbolKind = AssemblyOperand::SymbolKind::Static;
  staticSymbol.symbol = 0;
  global.operands = {functionSymbol, staticSymbol};
  p.globalAssembly = {global};
  p.libraries = {"native_support"};
  std::vector<Type> roots{closure};
  metadata::EncodeReferences refs;
  refs.type = [&](Type t) -> std::optional<std::uint32_t> {
    auto found = std::find(roots.begin(), roots.end(), t);
    if (found != roots.end())
      return static_cast<std::uint32_t>(found - roots.begin());
    roots.push_back(t);
    return static_cast<std::uint32_t>(roots.size() - 1);
  };
  refs.source = [](Span s) -> std::optional<metadata::SourceReference> {
    if (s.source != 0 && s.source != 7)
      return std::nullopt;
    return metadata::SourceReference{s.source == 7 ? "source-revision" : "",
                                     static_cast<std::uint32_t>(s.begin),
                                     static_cast<std::uint32_t>(s.end)};
  };
  refs.symbol = symbolName;
  auto encoded = encodeProgram(p, refs);
  require(bool(encoded), encoded.error.c_str());
  metadata::TypeGraphSymbols symbols;
  symbols.symbol = symbolName;
  symbols.definition =
      [&](Type t) -> std::optional<metadata::DefinitionIdentity> {
    return metadata::DefinitionIdentity{
        "core@revision", std::string(types->name(t)),
        t == parameter ? std::optional<std::uint32_t>{0} : std::nullopt};
  };
  auto graph = metadata::exportTypeGraph(*types, roots, symbols);
  require(bool(graph), graph.error.c_str());
  return {std::move(encoded.bytes), std::move(graph.bytes), roots.size()};
}
void verifiedRemapping() {
  auto fixture = encodeFixture();
  auto types = std::make_shared<TypeStore>();
  for (int i = 0; i < 9; ++i)
    types->declareParameter("consumer." + std::to_string(i), false);
  metadata::TypeGraphSymbols symbols;
  symbols.resolve = resolve;
  auto imported = metadata::importTypeGraph(*types, fixture.typeBytes, symbols);
  require(bool(imported), imported.error.c_str());
  require(imported.roots.size() == fixture.typeRoots, "shared roots lost");
  metadata::DecodeReferences refs;
  refs.type = [&](std::uint32_t index) -> std::optional<Type> {
    if (index >= imported.roots.size())
      return std::nullopt;
    return imported.roots[index];
  };
  refs.source = [](const metadata::SourceReference &r) -> std::optional<Span> {
    if (r.revision == "source-revision")
      return Span{r.begin, r.end, 43};
    if (r.revision.empty() && r.begin == 0 && r.end == 0)
      return Span{};
    return std::nullopt;
  };
  refs.symbol = resolve;
  auto decoded = decodeProgram(fixture.irBytes, refs);
  require(bool(decoded), decoded.error.c_str());
  require(decoded.functionIdentities[2] == *symbolName(SymbolKind::Function, 2),
          "private identity lost");
  require(
      decoded.functionDestinations ==
          std::vector<std::uint32_t>(destinations.begin(), destinations.end()),
      "function destination remapping lost");
  require(decoded.staticDestinations == std::vector<std::uint32_t>({2, 0, 1}),
          "static destination remapping lost");
  require(decoded.closureFunctions ==
              std::vector<std::pair<std::uint32_t, int>>({{3, 5}}),
          "closure identity used function domain");
  require(types->callable(imported.roots[0]).function == 3,
          "closure type graph link was not remapped");
  const auto &api = decoded.program.functions[0];
  require(
      api.blocks[0].instructions[1].callee == 3 &&
          api.blocks[0].instructions[2].callee == 2 &&
          decoded.program.functions[1].blocks[0].instructions[0].callee == 6 &&
          decoded.program.functions[2].blocks[0].instructions[1].callee == 0,
      "generic/default/private/external call references changed");
  require(api.locals[0].type.index() >= builtinTypeCount + 9 &&
              api.locals[0].scope == 1 && api.scopes[1].parent == 0 &&
              api.blocks[0].instructions[0].place.fields[0].index == 1 &&
              api.blocks[0].exit.first == 1 && api.blocks[0].exit.second == 2 &&
              api.blocks[3].instructions[0].predecessors ==
                  std::vector<int>({1, 2}) &&
              api.blocks[3].exit.value.id == 5 &&
              api.blocks[0].instructions[0].span.source == 43 &&
              api.span.source == 43 && api.inlineHint == InlineHint::Always &&
              api.floatingPolicy.reassociate && api.floatingPolicy.noNaNs &&
              api.floatingPolicy.noSignedZeros &&
              api.floatingPolicy.approximateFunctions &&
              !api.floatingPolicy.contract,
          "type/scope/place/SSA/source/policy metadata changed");
  require(decoded.program.functions[2].locals[0].staticIndex == 2 &&
              decoded.program.statics[1].initializer->symbol == 2 &&
              decoded.program.statics[1].initializer->byteOffset == 4 &&
              decoded.program.statics[2].initializer->symbol == 6 &&
              decoded.program.globalAssembly[0].operands[0].symbol == 6 &&
              decoded.program.globalAssembly[0].operands[1].symbol == 2,
          "static/constant/assembly symbol domains conflated");
  require(decoded.program.functions[1].locals[0].scope == -1 &&
              decoded.program.functions[1].locals[1].scope == -2,
          "inactive/escaping local scope sentinels changed");
  const auto &generic = decoded.program.functions[3];
  require(types->erased(generic.interfaceBounds[0].second).declaration == 91 &&
              generic.genericEqualities[0].parameter == generic.result &&
              generic.unpinBounds[0] == generic.result &&
              generic.sizedBounds == std::vector<Type>{generic.result} &&
              generic.genericResultSources == std::vector<std::size_t>{0},
          "generic interface contract changed");
  Program assembled;
  assembled.types = types;
  assembled.requireEntry = false;
  assembled.target = decoded.program.target;
  assembled.functions = {constantFunction("dependency.external", 11),
                         constantFunction("consumer", 12)};
  assembled.functions.resize(7);
  assembled.statics.resize(3);
  for (std::size_t i = 0; i < decoded.program.functions.size(); ++i)
    assembled.functions[decoded.functionDestinations[i]] =
        std::move(decoded.program.functions[i]);
  for (std::size_t i = 0; i < decoded.program.statics.size(); ++i)
    assembled.statics[decoded.staticDestinations[i]] =
        std::move(decoded.program.statics[i]);
  assembled.closureFunctions.assign(4, 0);
  for (auto [slot, function] : decoded.closureFunctions)
    assembled.closureFunctions[slot] = function;
  assembled.globalAssembly = std::move(decoded.program.globalAssembly);
  Diagnostics diagnostics;
  if (!verify(assembled, diagnostics)) {
    for (const auto &item : diagnostics.items)
      std::cerr << item.message << '\n';
    require(false,
            "remapped generic IR failed real structural/type verification");
  }
  auto malformed = assembled;
  malformed.statics[0].initializer->byteOffset = 2;
  Diagnostics misaligned;
  require(!verify(malformed, misaligned),
          "misaligned static interior relocation was accepted");
  malformed.statics[0].initializer->byteOffset = 8;
  Diagnostics outOfBounds;
  require(!verify(malformed, outOfBounds),
          "out-of-bounds static interior relocation was accepted");
  auto rawFixture = encodeFixture(true);
  auto rawDecoded = decodeProgram(rawFixture.irBytes, refs);
  require(bool(rawDecoded), rawDecoded.error.c_str());
  const auto &rawPointer = *rawDecoded.program.statics[1].initializer;
  require(rawPointer.kind == StaticConstant::Kind::Pointer &&
              rawPointer.scalar == integerLiteral(16) &&
              rawPointer.symbol == -1 && rawPointer.byteOffset == 0,
          "address-only constant pointer changed during codec round trip");
  auto rejected = [&](const std::vector<std::uint8_t> &bytes,
                      const metadata::DecodeReferences &mapping) {
    auto result = decodeProgram(bytes, mapping);
    require(!result && !result.error.empty() &&
                result.program.functions.empty() &&
                result.program.statics.empty() &&
                result.functionIdentities.empty() &&
                result.functionDestinations.empty() &&
                result.closureFunctions.empty(),
            "malformed archive exposed partial output");
  };
  for (std::size_t i = 0; i < fixture.irBytes.size(); ++i)
    rejected({fixture.irBytes.begin(), fixture.irBytes.begin() + i}, refs);
  auto bad = fixture.irBytes;
  bad.push_back(0);
  rejected(bad, refs);
  bad = fixture.irBytes;
  ++bad[4];
  rejected(bad, refs);
  bad = fixture.irBytes;
  std::fill_n(bad.begin() + 8, 4, 255);
  rejected(bad, refs);
  auto missing = refs;
  missing.type = {};
  rejected(fixture.irBytes, missing);
  missing = refs;
  missing.source = {};
  rejected(fixture.irBytes, missing);
  missing = refs;
  missing.symbol = {};
  rejected(fixture.irBytes, missing);
  missing = refs;
  missing.symbol = [](SymbolKind, std::string_view) {
    return std::optional<std::uint32_t>{0};
  };
  rejected(fixture.irBytes, missing);
  missing = refs;
  missing.symbol = [](SymbolKind, std::string_view) {
    return std::optional<std::uint32_t>{0xffffffff};
  };
  rejected(fixture.irBytes, missing);
  auto rootsBefore = imported.roots;
  for (std::size_t offset = 0; offset < fixture.irBytes.size(); ++offset) {
    bad = fixture.irBytes;
    bad[offset] ^= 0xff;
    auto result = decodeProgram(bad, refs);
    if (!result)
      require(result.program.functions.empty(),
              "mutated archive exposed partial records");
  }
  require(imported.roots == rootsBefore,
          "decode mutated shared caller type roots");
}
void literalBacking() {
  auto types = std::make_shared<TypeStore>();
  auto bytes = types->viewType(types->sliceType(Type::U8), ParameterMode::Read,
                               RegionId::Static);
  StaticConstant extent;
  extent.type = Type::Usize;
  extent.scalar = integerLiteral(2);
  StaticConstant literal;
  literal.kind = StaticConstant::Kind::Text;
  literal.type = bytes;
  literal.text = std::string("abc\0d", 5);
  literal.byteOffset = 2;
  literal.fields = {extent};
  Program program;
  program.types = types;
  program.requireEntry = false;
  program.statics = {{"LITERAL", {}, {}, bytes, false, false, {}, literal}};
  metadata::EncodeReferences encode;
  encode.type = [&](Type type) -> std::optional<std::uint32_t> {
    if (type == bytes)
      return 0;
    if (type == Type::Usize)
      return 1;
    return std::nullopt;
  };
  encode.symbol = symbolName;
  encode.source = [](Span span) {
    return std::optional{metadata::SourceReference{
        "literal-source", static_cast<std::uint32_t>(span.begin),
        static_cast<std::uint32_t>(span.end)}};
  };
  auto encoded = encodeProgram(program, encode);
  require(bool(encoded), encoded.error.c_str());
  metadata::DecodeReferences decode;
  decode.type = [&](std::uint32_t id) -> std::optional<Type> {
    if (id == 0)
      return bytes;
    if (id == 1)
      return Type::Usize;
    return std::nullopt;
  };
  decode.symbol = [](SymbolKind kind,
                     std::string_view name) -> std::optional<std::uint32_t> {
    return name == *symbolName(kind, 0) ? std::optional<std::uint32_t>{0}
                                        : std::nullopt;
  };
  decode.source =
      [](const metadata::SourceReference &source) -> std::optional<Span> {
    if (source.revision == "literal-source")
      return Span{source.begin, source.end, 7};
    return std::nullopt;
  };
  auto decoded = decodeProgram(encoded.bytes, decode);
  require(bool(decoded), decoded.error.c_str());
  decoded.program.types = types;
  auto &value = *decoded.program.statics[0].initializer;
  require(value.text == literal.text && value.byteOffset == 2 &&
              value.fields.size() == 1 &&
              value.fields[0].scalar == extent.scalar,
          "literal backing, interior offset or extent lost in codec");
  Diagnostics valid;
  require(verify(decoded.program, valid),
          "valid literal interior view was rejected");
  value.fields[0].scalar = integerLiteral(4);
  Diagnostics excessive;
  require(!verify(decoded.program, excessive),
          "literal extent beyond backing was accepted");
  value.byteOffset = value.text.size();
  value.fields[0].scalar = integerLiteral(0);
  Diagnostics empty;
  require(verify(decoded.program, empty),
          "empty one-past literal view was rejected");
  value.fields[0].scalar = integerLiteral(1);
  Diagnostics pastEnd;
  require(!verify(decoded.program, pastEnd),
          "nonempty one-past literal view was accepted");
}
void rawFieldCoverage() {
  Program p;
  p.requireEntry = false;
  auto function = constantFunction("metadata", 0);
  function.parameters = 1;
  function.locals = {{"argument", Type::I32, true, {}, ParameterMode::Mut}};
  function.scopes.push_back({0});
  function.resultSources = function.resultContents =
      function.callLocalParameters = function.genericResultSources = {0};
  function.withinFlows = {{0, 0}};
  function.externalName = "external";
  function.twoPhaseReceiver = function.indirectContract =
      function.declarationOnly = function.unsafeFunction =
          function.foreignDeclaration = function.exportedDefinition =
              function.variadic = function.coroutine = true;
  function.constructorSelfSlot = function.variadicCursor = 0;
  function.genericParameters = function.unpinBounds = {Type::I32};
  function.interfaceBounds = {{Type::I32, Type::Unit}};
  function.genericEqualities = {{Type::I32, Type::U32}};
  function.regionSignature = Type::Bool;
  function.interfaceResult = Type::Char;
  function.abi = "C";
  function.targetFeatures = {"sse2"};
  function.inlineHint = InlineHint::Never;
  function.floatingPolicy = {true, true, true, true, true, true, true};
  Assembly assembly;
  assembly.variant = AssemblyVariant::Naked;
  assembly.templates = {"ret"};
  assembly.options = {"nostack"};
  assembly.clobberAbis = {"C"};
  AssemblyOperand operand;
  operand.mode = AssemblyMode::Sym;
  operand.symbolKind = AssemblyOperand::SymbolKind::Static;
  operand.symbol = 7;
  operand.name = "operand";
  operand.reg = "rax";
  operand.explicitRegister = operand.discard = true;
  operand.type = Type::I32;
  operand.inputType = Type::U32;
  operand.constantIdentity = Type::U64;
  operand.constant.magnitude = {0xfedcba9876543210, 0x123456789abcdef0};
  operand.symbolArguments = {Type::I32};
  assembly.operands = {operand};
  function.nakedAssembly = assembly;
  auto &n = function.blocks[0].instructions[0];
  n.op = Op::Assembly;
  n.result.type = Type::I128;
  n.operands = {{0, Type::I32, Access::Mut}};
  n.predecessors = {0};
  n.text = "LOCAL_REFERENCE_SENTINEL";
  n.place = {0,
             {{Projection::Kind::Slice, 4, 9, Type::U8},
              Projection::opaque(Type::U32)}};
  n.callee = 9;
  n.number = -1234567;
  n.target = {0, Type::U32, Access::Read};
  n.indirectType = Type::Bool;
  n.callLocalParameters = {0};
  n.typeArguments = {Type::U64};
  n.constantParameter = Type::U8;
  n.interfaceType = Type::I8;
  n.interfaceSelf = Type::I16;
  n.interfaceMethod = 17;
  n.dropFunction = 8;
  n.erasedDispatch = n.unsafeAllowed = true;
  n.opaqueType = Type::I64;
  n.witnessEntries = {{Type::I8, 18}};
  n.numeric =
      NumericLiteral{{0xfedcba9876543210, 0x123456789abcdef0}, {}, true, {}};
  n.unpinProofs = {{Type::I8, Type::U8}};
  n.assembly = assembly;
  n.scope = 1;
  function.arrayLoops = {
      {0, 0, 0, 0, {0}, {0, {}}, {0, Type::Usize}, 0, ParameterMode::Take}};
  p.functions = {function};
  p.opaqueAdapters = {{Type::U32, Type::I8, 17, 8, {Type::U64}}};
  p.coroutines = {{Type::I64, 9}};
  p.dynamicDropFunctions = {{Type::U64, 8}};
  p.globalAssembly = {assembly};
  StaticConstant constant;
  constant.kind = StaticConstant::Kind::Repeat;
  constant.type = Type::F64;
  StaticConstant element;
  element.type = Type::F64;
  element.scalar.floatingBits = 0xfff8000012345678;
  constant.fields = {element};
  constant.projections = {0, 1};
  constant.selection = 2;
  constant.text = std::string("bytes\0tail", 10);
  p.statics = {
      {"bits", "BITS", "native", Type::F64, true, false, {9, 10, 7}, constant}};
  metadata::EncodeReferences encode;
  encode.type = [](Type type) { return std::optional{type.index() + 100}; };
  encode.source = [](Span s) {
    return std::optional{metadata::SourceReference{
        "revision", static_cast<std::uint32_t>(s.begin),
        static_cast<std::uint32_t>(s.end)}};
  };
  encode.symbol = symbolName;
  auto bytes = encodeProgram(p, encode);
  require(bool(bytes), bytes.error.c_str());
  metadata::DecodeReferences decode;
  decode.type = [](std::uint32_t id) -> std::optional<Type> {
    constexpr std::array types{
        Type::Unknown, Type::I32,   Type::Bool, Type::Unit, Type::Never,
        Type::Char,    Type::U8,    Type::I8,   Type::I16,  Type::I64,
        Type::I128,    Type::Isize, Type::U16,  Type::U32,  Type::U64,
        Type::U128,    Type::Usize, Type::F32,  Type::F64};
    if (id < 100 || id - 100 >= types.size())
      return std::nullopt;
    return types[id - 100];
  };
  decode.source = [](const metadata::SourceReference &r) {
    return std::optional{Span{r.begin, r.end, 81}};
  };
  decode.symbol = [](SymbolKind kind,
                     std::string_view name) -> std::optional<std::uint32_t> {
    for (std::uint32_t i = 0; i < 10; ++i)
      if (name == *symbolName(kind, i))
        return i + (kind == SymbolKind::Static ? 200 : 100);
    return std::nullopt;
  };
  auto result = decodeProgram(bytes.bytes, decode);
  require(bool(result), result.error.c_str());
  const auto &f = result.program.functions[0];
  const auto &r = f.blocks[0].instructions[0];
  require(f.resultSources == function.resultSources &&
              f.resultContents == function.resultContents &&
              f.withinFlows == function.withinFlows &&
              f.callLocalParameters == function.callLocalParameters &&
              f.genericResultSources == function.genericResultSources &&
              f.externalName == "external" && f.twoPhaseReceiver &&
              f.indirectContract && f.declarationOnly && f.unsafeFunction &&
              f.foreignDeclaration && f.exportedDefinition && f.variadic &&
              f.coroutine && f.constructorSelfSlot == 0 &&
              f.variadicCursor == 0 && f.regionSignature == Type::Bool &&
              f.interfaceResult == Type::Char && f.abi == "C" &&
              f.inlineHint == InlineHint::Never && f.floatingPolicy.contract &&
              f.floatingPolicy.noInfinities && f.floatingPolicy.reciprocal,
          "function semantic metadata lost");
  require(r.op == n.op && r.result.id == n.result.id &&
              r.operands[0].access == Access::Mut && r.predecessors[0] == 0 &&
              r.text == n.text && r.place == n.place && r.callee == 109 &&
              r.number == -1234567 && r.target.type == Type::U32 &&
              r.target.access == Access::Read && r.indirectType == Type::Bool &&
              r.callLocalParameters == n.callLocalParameters &&
              r.typeArguments == n.typeArguments &&
              r.constantParameter == Type::U8 && r.interfaceType == Type::I8 &&
              r.interfaceSelf == Type::I16 && r.interfaceMethod == 17 &&
              r.dropFunction == 108 && r.erasedDispatch && r.unsafeAllowed &&
              r.opaqueType == Type::I64 && r.witnessEntries[0].method == 18 &&
              r.numeric == n.numeric && r.unpinProofs == n.unpinProofs &&
              r.scope == 1 && f.arrayLoops[0].element == 0 &&
              f.arrayLoops[0].mode == ParameterMode::Take &&
              result.program.opaqueAdapters[0].function == 108 &&
              result.program.opaqueAdapters[0].method == 17 &&
              result.program.coroutines[0].second == 109 &&
              result.program.dynamicDropFunctions[0].second == 108,
          "instruction/loop/adapter/coroutine metadata lost");
  const auto &a = *r.assembly;
  const auto &o = a.operands[0];
  require(a.variant == AssemblyVariant::Naked &&
              a.templates == assembly.templates &&
              a.options == assembly.options &&
              a.clobberAbis == assembly.clobberAbis && o.mode == operand.mode &&
              o.name == operand.name && o.reg == operand.reg &&
              o.explicitRegister && o.discard && o.type == Type::I32 &&
              o.inputType == Type::U32 && o.constant == operand.constant &&
              o.constantIdentity == Type::U64 && o.symbol == 207 &&
              o.symbolArguments == operand.symbolArguments &&
              f.nakedAssembly->operands[0].symbol == 207 &&
              result.program.globalAssembly[0].operands[0].symbol == 207,
          "assembly operand metadata lost");
  const auto &c = *result.program.statics[0].initializer;
  require(c.fields[0].scalar.floatingBits == element.scalar.floatingBits &&
              c.projections == constant.projections && c.selection == 2 &&
              c.text == constant.text,
          "static exact bits/aggregate/projection/text metadata lost");
  auto bad = bytes.bytes;
  auto marker =
      std::search(bad.begin(), bad.end(), n.text.begin(), n.text.end());
  require(marker != bad.end(), "missing corruption probe marker");
  std::fill_n(marker + n.text.size(), 4, 0x7f);
  require(!decodeProgram(bad, decode), "dangling owned place accepted");
  auto malformed = p;
  malformed.functions[0].blocks[0].instructions[0].operands[0].id = 123;
  require(!encodeProgram(malformed, encode), "dangling SSA operand exported");
  malformed = p;
  malformed.functions[0].blocks[0].instructions[0].callee = -2;
  require(!encodeProgram(malformed, encode),
          "negative symbol cast to unsigned");
  malformed = p;
  malformed.functions[0].locals[0].scope = -3;
  require(!encodeProgram(malformed, encode),
          "invalid negative local scope accepted");
  malformed = p;
  malformed.statics[0].initializer->fields[0].scalar.magnitude[0] = 1;
  require(!encodeProgram(malformed, encode), "conflicting exact bits exported");
  Program empty;
  auto minimal = encodeProgram(empty, encode);
  require(bool(minimal), minimal.error.c_str());
  bad = minimal.bytes;
  bad[24] = 2;
  require(!decodeProgram(bad, decode), "invalid boolean accepted");
  bad = minimal.bytes;
  bad[29] = 255;
  require(!decodeProgram(bad, decode), "invalid enum tag accepted");
}
} // namespace
int main() {
  try {
    verifiedRemapping();
    literalBacking();
    rawFieldCoverage();
    std::cout << "IR codec tests passed\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
