#include "expansion/detail.h"
#include "syntax/parser.h"
#include "syntax/token.h"
#include <algorithm>
#include <cctype>
#include <functional>
#include <map>

namespace mettle::expansion {
namespace {
struct DeriveInfo {
  const char *module, *interface;
};
const std::map<std::string, DeriveInfo> &catalog() {
  static const std::map<std::string, DeriveInfo> entries{
      {"Clone", {"clone", "Clone"}}, {"Copy", {"marker", "Copy"}},   {"Debug", {"fmt", "Debug"}},
      {"PartialEq", {"cmp", "PartialEq"}}, {"Eq", {"cmp", "Eq"}},
      {"PartialOrd", {"cmp", "PartialOrd"}}, {"Ord", {"cmp", "Ord"}},
      {"Hash", {"hash", "Hash"}}};
  return entries;
}
const std::string core = "package::core::";

std::string identifier(const std::string &name) {
  auto plain = !name.empty() &&
               (std::isalpha(static_cast<unsigned char>(name[0])) ||
                name[0] == '_') &&
               std::all_of(name.begin(), name.end(), [](char c) {
                 return std::isalnum(static_cast<unsigned char>(c)) ||
                        c == '_';
               });
  return plain && !isReservedWord(name) ? name : "`" + name + "`";
}

bool mentions(const TypeSyntax &type, const std::string &name) {
  if (type.name == name || (type.nested && mentions(*type.nested, name)))
    return true;
  for (const auto &element : type.elements)
    if (mentions(element, name))
      return true;
  for (const auto &argument : type.arguments)
    if (argument.type && mentions(*argument.type, name))
      return true;
  if (type.callable) {
    for (const auto &parameter : type.callable->parameters)
      if (mentions(parameter.annotation, name))
        return true;
    return mentions(type.callable->result, name) ||
           mentions(type.callable->error, name);
  }
  return false;
}

class Generator {
public:
  Generator(Module &module, std::size_t index, const DeriveRequest &request,
            const std::string &interface, Diagnostics &diagnostics,
            const SourceAllocator &allocate)
      : module(module), product(module.products[index]), request(request),
        interface(interface), diagnostics(diagnostics), allocate(allocate) {}

  void run() {
    header();
    if (interface == "Clone")
      clone();
    else if (interface == "Debug")
      debug();
    else if (interface == "PartialEq")
      equality();
    else if (interface == "Eq") {
      // Marker interface: the empty impl asserts the derived PartialEq.
    } else if (interface == "Hash")
      hash();
    else
      ordering(interface == "PartialOrd");
    out += "}\n";
    install();
  }

private:
  Module &module;
  Module::Product &product;
  const DeriveRequest &request;
  std::string interface;
  Diagnostics &diagnostics;
  const SourceAllocator &allocate;
  std::string out, target, path;
  std::vector<Generation::Mapping> mappings;
  std::vector<const Parameter *> fieldTypes;

  // One described unit of data: a product body or one enum variant.
  struct Shape {
    std::string constructor, label;
    const std::vector<Parameter> *fields;
    bool positional, product;
    std::size_t index;
  };

  void put(const std::string &text) { out += text; }
  template <typename F> void mapped(const Parameter &field, F emit) {
    auto begin = out.size();
    emit();
    mappings.push_back({begin, out.size(), field.span});
  }

  void header() {
    path = core + std::string(catalog().at(interface).module) +
           "::" + interface;
    target = identifier(product.name);
    std::string arguments;
    for (const auto &parameter : product.genericParameters) {
      arguments += arguments.empty() ? "<" : ", ";
      if (parameter.kind == GenericParameterKind::Const)
        arguments += "const ";
      else if (parameter.kind == GenericParameterKind::Region)
        arguments += "region ";
      arguments += identifier(parameter.name);
    }
    target += arguments.empty() ? "" : arguments + ">";
    put("impl " + target + " implements " + path + " {\n");
  }

  std::string projection(const Parameter &field) {
    return projectionOf(field, interface,
                        catalog().at(interface).module);
  }
  std::string projectionOf(const Parameter &field,
                           const std::string &interfaceName,
                           const std::string &module) {
    fieldTypes.push_back(&field);
    auto placeholder = "__T" + std::to_string(fieldTypes.size() - 1);
    // The comparison interfaces take the right-hand type explicitly.
    auto argument = interfaceName == "PartialEq" || interfaceName == "PartialOrd"
                        ? "<" + placeholder + ">"
                        : "";
    return "<" + placeholder + " implements " + core + module +
           "::" + interfaceName + argument + ">";
  }

  std::vector<Shape> shapes() const {
    std::vector<Shape> result;
    if (!product.enumeration) {
      result.push_back({identifier(product.name), product.name,
                        &product.fields, false, true, 0});
      return result;
    }
    for (const auto &variant : product.variants) {
      auto positional = !variant.fields.empty() &&
                        std::isdigit(static_cast<unsigned char>(
                            variant.fields.front().name[0]));
      result.push_back({identifier(product.name) +
                            "::" + identifier(variant.name),
                        variant.name, &variant.fields, positional, false,
                        result.size()});
    }
    return result;
  }

  std::string binding(const Shape &shape, const char *prefix,
                      bool wildcard) const {
    auto fields = shape.fields;
    if (fields->empty())
      return shape.constructor;
    std::string text = shape.constructor + (shape.positional ? "(" : " { ");
    for (std::size_t i = 0; i < fields->size(); ++i) {
      if (i)
        text += ", ";
      auto bound = wildcard ? "_" : prefix + std::to_string(i);
      text += shape.positional ? bound
                               : identifier((*fields)[i].name) + ": " + bound;
    }
    return text + (shape.positional ? ")" : " }");
  }
  std::string shapePattern(const Shape &shape, const char *prefix) const {
    return binding(shape, prefix, false);
  }
  std::string indexPattern(const Shape &shape) const {
    if (shape.fields->empty())
      return shape.constructor;
    if (shape.positional)
      return binding(shape, "", true);
    return shape.constructor + " { .. }";
  }
  std::string access(const Shape &shape, const char *base, const char *prefix,
                     std::size_t i) const {
    if (shape.product)
      return std::string(base) + "." + identifier((*shape.fields)[i].name);
    return prefix + std::to_string(i);
  }

  template <typename Body> void matchOn(const char *subject, Body body) {
    put(std::string("match ") + subject + " {\n");
    for (const auto &shape : shapes()) {
      put(shapePattern(shape, subject[0] == 's' ? "__l" : "__r") + " => {\n");
      body(shape);
      put("},\n");
    }
    put("}\n");
  }

  void clone() {
    put("fn clone(): " + target + " {\n");
    auto construct = [&](const Shape &shape) {
      put(shape.constructor + "(");
      for (std::size_t i = 0; i < shape.fields->size(); ++i) {
        const auto &field = (*shape.fields)[i];
        if (i)
          put(", ");
        if (!shape.positional)
          put(identifier(field.name) + ": ");
        mapped(field, [&] {
          put(projection(field) + "::clone(" + access(shape, "self", "__l", i) +
              ")");
        });
      }
      put(")\n");
    };
    if (!product.enumeration)
      construct(shapes().front());
    else
      matchOn("self", [&](const Shape &shape) {
        if (shape.fields->empty())
          put(shape.constructor + "\n");
        else
          construct(shape);
      });
    put("}\n");
  }

  void debug() {
    put("fn fmt<__W: " + core + "fmt::Write>(f: mut " + core +
        "fmt::Formatter<__W>): Unit throws " + core + "fmt::Error {\n");
    auto emit = [&](const Shape &shape) {
      auto &fields = *shape.fields;
      put("try f.write_str(\"" + shape.label + "\")\n");
      if (fields.empty())
        return;
      put(shape.positional ? "try f.debug_open(\"(\")\n"
                           : "try f.debug_open(\" {\")\nif !f.options()"
                             ".alternate { try f.write_str(\" \") }\n");
      for (std::size_t i = 0; i < fields.size(); ++i) {
        put(std::string("try f.debug_item_start(") + (i ? "false" : "true") +
            ")\n");
        if (!shape.positional)
          put("try f.write_str(\"" + fields[i].name + ": \")\n");
        mapped(fields[i], [&] {
          put("try " + projection(fields[i]) + "::fmt(" +
              access(shape, "self", "__l", i) + ", mut f)");
        });
        put("\ntry f.debug_item_end()\n");
      }
      if (shape.positional)
        put("try f.debug_close(\")\", false)\n");
      else
        put("if !f.options().alternate { try f.write_str(\" \") }\n"
            "try f.debug_close(\"}\", false)\n");
    };
    if (!product.enumeration)
      emit(shapes().front());
    else {
      put("match self {\n");
      for (const auto &shape : shapes()) {
        put(shapePattern(shape, "__l") + " => {\n");
        emit(shape);
        put("},\n");
      }
      put("}\n");
    }
    put("}\n");
  }

  void equalityChain(const Shape &left) {
    if (left.fields->empty())
      return put("true\n");
    for (std::size_t i = 0; i < left.fields->size(); ++i) {
      const auto &field = (*left.fields)[i];
      if (i)
        put(" && ");
      mapped(field, [&] {
        put(projection(field) + "::eq(" + access(left, "self", "__l", i) +
            ", read " + access(left, "other", "__r", i) + ")");
      });
    }
    put("\n");
  }

  void equality() {
    put("fn eq(other: read " + target + "): bool {\n");
    if (!product.enumeration)
      equalityChain(shapes().front());
    else {
      auto all = shapes();
      put("match self {\n");
      for (const auto &shape : all) {
        put(shapePattern(shape, "__l") + " => {\nmatch other {\n" +
            shapePattern(shape, "__r") + " => {\n");
        equalityChain(shape);
        put("},\n");
        if (all.size() > 1)
          put("_ => { false },\n");
        put("}\n},\n");
      }
      put("}\n");
    }
    put("}\n");
  }

  void orderingChain(const Shape &shape, bool partial) {
    std::string equal = core + "cmp::Ordering::Equal";
    auto wrapped = partial ? "present(" + equal + ")" : equal;
    auto call = [&](const Parameter &field, std::size_t i) {
      mapped(field, [&] {
        put(projectionOf(field, partial ? "PartialOrd" : "Ord", "cmp") +
            "::" + (partial ? "partial_cmp(" : "cmp(") +
            access(shape, "self", "__l", i) + ", read " +
            access(shape, "other", "__r", i) + ")");
      });
    };
    auto count = shape.fields->size();
    if (!count)
      return put(wrapped + "\n");
    for (std::size_t i = 0; i + 1 < count; ++i) {
      auto name = "__c" + std::to_string(i);
      put("let " + name + " = ");
      call((*shape.fields)[i], i);
      put("\nmatch " + name + " {\n" + wrapped + " => {},\n_ => { return " +
          name + " },\n}\n");
    }
    call((*shape.fields)[count - 1], count - 1);
    put("\n");
  }

  void ordering(bool partial) {
    put(partial ? "fn partial_cmp(other: read " + target + "): " + core +
                      "cmp::Ordering? {\n"
                : "fn cmp(other: read " + target + "): " + core +
                      "cmp::Ordering {\n");
    if (!product.enumeration)
      orderingChain(shapes().front(), partial);
    else {
      auto all = shapes();
      if (all.size() > 1) {
        for (auto side : {"self", "other"}) {
          put(std::string("let __") + (side[0] == 's' ? "li" : "ri") +
              " = match " + side + " {\n");
          for (const auto &shape : all)
            put(indexPattern(shape) + " => " + std::to_string(shape.index) +
                "usize,\n");
          put("}\n");
        }
        put("if __li != __ri { return <usize implements " + core + "cmp::" +
            (partial ? "PartialOrd<usize>>::partial_cmp" : "Ord>::cmp") +
            "(__li, read __ri) }\n");
      }
      put("match self {\n");
      for (const auto &shape : all) {
        put(shapePattern(shape, "__l") + " => {\nmatch other {\n" +
            shapePattern(shape, "__r") + " => {\n");
        orderingChain(shape, partial);
        put("},\n");
        if (all.size() > 1) {
          put("_ => { ");
          put(partial ? "present(" + core + "cmp::Ordering::Equal)"
                      : core + "cmp::Ordering::Equal");
          put(" },\n");
        }
        put("}\n},\n");
      }
      put("}\n");
    }
    put("}\n");
  }

  void hash() {
    put("fn hash<__H: " + core + "hash::Hasher>(state: mut __H): Unit {\n");
    auto emit = [&](const Shape &shape) {
      if (product.enumeration)
        put("<usize implements " + core + "hash::Hash>::hash(" +
            std::to_string(shape.index) + "usize, mut state)\n");
      for (std::size_t i = 0; i < shape.fields->size(); ++i) {
        const auto &field = (*shape.fields)[i];
        mapped(field, [&] {
          put(projection(field) + "::hash(" + access(shape, "self", "__l", i) +
              ", mut state)");
        });
        put("\n");
      }
    };
    if (!product.enumeration)
      emit(shapes().front());
    else
      matchOn("self", emit);
    put("}\n");
  }

  static void substitute(TypeSyntax &type,
                         const std::vector<const Parameter *> &fields) {
    if (type.name.starts_with("__T") && type.form == TypeForm::Named &&
        type.name.size() > 3 &&
        std::all_of(type.name.begin() + 3, type.name.end(), [](char c) {
          return std::isdigit(static_cast<unsigned char>(c));
        })) {
      type = fields[std::stoul(type.name.substr(3))]->annotation;
      return;
    }
    if (type.nested) {
      auto copy = *type.nested;
      substitute(copy, fields);
      type.nested = std::make_shared<const TypeSyntax>(std::move(copy));
    }
    for (auto &element : type.elements)
      substitute(element, fields);
    for (auto &argument : type.arguments)
      if (argument.type) {
        auto copy = *argument.type;
        substitute(copy, fields);
        argument.type = std::make_shared<const TypeSyntax>(std::move(copy));
      }
  }

  static void patch(Node &node, const std::vector<const Parameter *> &fields) {
    substitute(node.annotation, fields);
    for (auto &child : node.children)
      if (child.get())
        patch(*child, fields);
  }

  void install() {
    auto description =
        "derive(" + request.name + ") for '" + product.name + "'";
    Source source{"<" + description + ">", out, allocate()};
    Diagnostics::SourceContext context(diagnostics, source);
    diagnostics.generated(
        {source.id, request.span, description, std::move(mappings)});
    auto before = diagnostics.items.size();
    auto generated = parseDeclarations(source, diagnostics);
    if (diagnostics.items.size() != before || generated.implementations.size() != 1)
      return;
    auto implementation = std::move(generated.implementations.front());
    for (auto &method : implementation.methods)
      if (method.body.get())
        patch(*method.body, fieldTypes);
    implementation.genericParameters = product.genericParameters;
    for (auto &parameter : implementation.genericParameters) {
      parameter.defaultType = {};
      parameter.defaultValue = {};
      if (parameter.kind != GenericParameterKind::Type)
        continue;
      auto used = [&](const Parameter &field) {
        return mentions(field.annotation, parameter.name);
      };
      auto &fields = product.fields;
      auto occurs = std::any_of(fields.begin(), fields.end(), used) ||
                    std::any_of(product.variants.begin(),
                                product.variants.end(), [&](const auto &variant) {
                                  return std::any_of(variant.fields.begin(),
                                                     variant.fields.end(), used);
                                });
      if (occurs)
        parameter.bounds.push_back(implementation.interface);
    }
    implementation.constraints = product.constraints;
    implementation.item.scope = product.item.scope;
    for (auto &method : implementation.methods)
      method.item.scope = product.item.scope;
    module.tokens.insert(module.tokens.end(), generated.tokens.begin(),
                         generated.tokens.end());
    module.textLiterals.insert(module.textLiterals.end(),
                               generated.textLiterals.begin(),
                               generated.textLiterals.end());
    module.implementations.push_back(std::move(implementation));
  }
};
} // namespace

std::vector<DeriveRequest> deriveRequests(const Attribute &attribute,
                                          std::set<std::string> &requested,
                                          Diagnostics &diagnostics) {
  std::vector<DeriveRequest> result;
  const auto &tokens = attribute.arguments;
  if (!attribute.parenthesized || tokens.empty()) {
    diagnostics.error("attribute", attribute.span,
                      "derive requires a parenthesized list of interfaces");
    return result;
  }
  std::size_t position = 0;
  while (position < tokens.size()) {
    std::string path;
    auto span = tokens[position].span;
    while (position < tokens.size() && tokens[position].kind == TokenKind::Word) {
      path += tokens[position].text;
      span.end = tokens[position].span.end;
      ++position;
      if (position < tokens.size() && tokens[position].text == "::") {
        path += "::";
        ++position;
      } else
        break;
    }
    if (path.empty() || path.ends_with("::")) {
      diagnostics.error("attribute", tokens[std::min(position, tokens.size() - 1)].span,
                        "expected an interface name in derive(...)");
      return result;
    }
    auto name = path.substr(path.rfind(':') == std::string::npos
                                ? 0
                                : path.rfind(':') + 1);
    auto found = catalog().find(name);
    auto qualified = name != path;
    if (name == "Default" && !qualified)
      diagnostics.error("feature", span,
                        "derive(Default) requires a Default interface in "
                        "library/core, which does not exist yet");
    else if (found == catalog().end() ||
             (qualified &&
              path != "core::" + std::string(found->second.module) + "::" +
                          name &&
              path != core + std::string(found->second.module) + "::" + name))
      diagnostics.error("attribute", span,
                        "unknown derive '" + path +
                            "'; derivable interfaces are Clone, Copy, Debug, "
                            "PartialEq, Eq, PartialOrd, Ord and Hash");
    else if (!requested.insert(name).second)
      diagnostics.error("attribute", span,
                        "'" + name + "' is already derived on this type");
    else
      result.push_back({name, span});
    if (position < tokens.size()) {
      if (tokens[position].text != ",") {
        diagnostics.error("attribute", tokens[position].span,
                          "expected ',' between derive names");
        return result;
      }
      ++position;
    }
  }
  return result;
}

void generateDerives(Module &module, std::size_t index,
                     const std::vector<DeriveRequest> &requests,
                     Diagnostics &diagnostics, const SourceAllocator &allocate) {
  auto &product = module.products[index];
  auto unsupported = [&](const DeriveRequest &request, const std::string &why) {
    diagnostics.error("feature", request.span,
                      "derive(" + request.name + ") " + why);
  };
  for (const auto &request : requests) {
    if (request.name == "Copy") {
      if (product.copyRequested)
        diagnostics.error("attribute", request.span,
                          "'" + product.name + "' is already a copy type");
      product.copyRequested = true;
      continue;
    }
    if (product.unionType)
      unsupported(request, "is not implemented for unions");
    else if (product.enumeration && product.variants.empty())
      unsupported(request, "is not implemented for enums without variants");
    else if (std::any_of(product.methods.begin(), product.methods.end(),
                         [](const Function &method) {
                           return method.constructor;
                         }))
      unsupported(request,
                  "is not implemented for types with an init constructor");
    else
      Generator(module, index, request, request.name, diagnostics, allocate)
          .run();
  }
}
} // namespace mettle::expansion
