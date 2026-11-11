#include "syntax/fingerprint.h"
#include <map>

namespace mettle {
namespace {
struct Fingerprint {
  std::string text;
  std::map<std::uint64_t, std::size_t> contexts;
};
void typeFingerprint(const TypeSyntax &type, Fingerprint &state);
void nodeFingerprint(const Node &node, Fingerprint &state);

void contextFingerprint(const SyntaxContextPtr &context, Fingerprint &state) {
  if (!context)
    return;
  std::size_t identity = 0;
  if (context->identity)
    identity =
        state.contexts.try_emplace(context->identity, state.contexts.size() + 1)
            .first->second;
  auto &out = state.text;
  out += " context(" + std::to_string(identity);
  for (const auto &part : context->scope)
    out += ' ' + std::to_string(part.size()) + ':' + part;
  out += ')';
}

void patternFingerprint(const Pattern &pattern, Fingerprint &state) {
  auto &out = state.text;
  out += "P(" + std::to_string(static_cast<int>(pattern.kind)) + ' ' +
         pattern.text + ' ' + pattern.field;
  contextFingerprint(pattern.context, state);
  contextFingerprint(pattern.fieldContext, state);
  for (const auto &child : pattern.children)
    patternFingerprint(child, state);
  out += ')';
}
void argumentsFingerprint(const std::vector<GenericArgument> &arguments,
                          Fingerprint &state) {
  auto &out = state.text;
  out += '<';
  for (const auto &argument : arguments) {
    out += argument.binding + '=' + argument.region.spelling;
    contextFingerprint(argument.region.context, state);
    if (argument.type)
      typeFingerprint(*argument.type, state);
    if (argument.value)
      nodeFingerprint(*argument.value, state);
    out += ',';
  }
  out += '>';
}
void typeFingerprint(const TypeSyntax &type, Fingerprint &state) {
  auto &out = state.text;
  out += "T(" + std::to_string(static_cast<int>(type.form)) + ' ' + type.view +
         ' ' + type.name;
  contextFingerprint(type.context, state);
  if (type.form == TypeForm::Owner)
    out += " owner " + std::to_string(static_cast<int>(type.ownerKind));
  for (const auto &source : type.sources) {
    out += " from " + source.spelling;
    contextFingerprint(source.context, state);
  }
  for (const auto &region : type.regions) {
    out += " region " + region.spelling;
    contextFingerprint(region.context, state);
  }
  for (const auto &binder : type.binders) {
    out += " for " + binder.spelling;
    contextFingerprint(binder.context, state);
  }
  if (type.nested)
    typeFingerprint(*type.nested, state);
  for (const auto &element : type.elements)
    typeFingerprint(element, state);
  argumentsFingerprint(type.arguments, state);
  if (type.countExpression)
    nodeFingerprint(*type.countExpression, state);
  if (type.callable) {
    const auto &callable = *type.callable;
    out += " callable " + callable.mode + ' ' + callable.abi;
    for (const auto &region : callable.regions) {
      out += " for " + region.spelling;
      contextFingerprint(region.context, state);
    }
    for (const auto &parameter : callable.parameters) {
      out += parameter.mode + ' ';
      typeFingerprint(parameter.annotation, state);
    }
    typeFingerprint(callable.result, state);
    typeFingerprint(callable.error, state);
  }
  out += ')';
}
void nodeFingerprint(const Node &node, Fingerprint &state) {
  auto &out = state.text;
  out += "K(" + std::to_string(static_cast<int>(node.kind)) + ' ' + node.text +
         ' ' + node.name + ' ' + node.label + (node.flag ? " 1" : " 0") +
         (node.semicolon ? ";" : "");
  contextFingerprint(node.context, state);
  if (!node.name.empty()) {
    out += " field";
    contextFingerprint(node.fieldContext, state);
  }
  typeFingerprint(node.annotation, state);
  typeFingerprint(node.error, state);
  for (const auto &pattern : node.patterns)
    patternFingerprint(pattern, state);
  for (const auto &parameter : node.parameters) {
    out += parameter.name + ':' + parameter.mode;
    contextFingerprint(parameter.context, state);
    typeFingerprint(parameter.annotation, state);
    if (parameter.pattern)
      patternFingerprint(*parameter.pattern, state);
  }
  argumentsFingerprint(node.ownerGenericArguments, state);
  argumentsFingerprint(node.genericArguments, state);
  for (const auto &child : node.children)
    nodeFingerprint(*child, state);
  out += ')';
}
} // namespace

std::string fingerprint(const Module &module) {
  Fingerprint state;
  auto &out = state.text;
  for (const auto &function : module.functions) {
    out += "F(" + function.name + ' ' + function.receiver + ' ' +
           function.owner + ' ';
    contextFingerprint(function.lexicalContext, state);
    for (const auto &parameter : function.parameters) {
      out += parameter.name + ':' + parameter.mode + ' ';
      contextFingerprint(parameter.context, state);
      typeFingerprint(parameter.annotation, state);
      if (parameter.pattern)
        patternFingerprint(*parameter.pattern, state);
      if (parameter.defaultValue.get())
        nodeFingerprint(*parameter.defaultValue, state);
    }
    typeFingerprint(function.annotation, state);
    typeFingerprint(function.error, state);
    for (const auto &generic : function.genericParameters) {
      out += generic.name;
      contextFingerprint(generic.context, state);
      for (const auto &bound : generic.bounds)
        typeFingerprint(bound, state);
    }
    for (const auto &constraint : function.constraints) {
      typeFingerprint(constraint.subject, state);
      for (const auto &bound : constraint.bounds)
        typeFingerprint(bound, state);
      if (constraint.equality)
        typeFingerprint(*constraint.equality, state);
    }
    if (function.body.get())
      nodeFingerprint(*function.body, state);
    out += ")\n";
  }
  for (const auto &product : module.products) {
    out += "D(" + product.name;
    contextFingerprint(product.nameContext, state);
    for (const auto &field : product.fields) {
      out += ' ' + field.name;
      contextFingerprint(field.context, state);
      typeFingerprint(field.annotation, state);
    }
    for (const auto &variant : product.variants) {
      out += " variant " + variant.name;
      for (const auto &field : variant.fields) {
        contextFingerprint(field.context, state);
        typeFingerprint(field.annotation, state);
      }
    }
    for (const auto &interface : product.interfaces)
      typeFingerprint(interface, state);
    out += ")\n";
  }
  for (const auto &implementation : module.implementations) {
    out += std::string("I(") + (implementation.negative ? "not " : "") +
           (implementation.unsafeImplementation ? "unsafe " : "") +
           (implementation.shorthand ? "shorthand " : "");
    typeFingerprint(implementation.target, state);
    typeFingerprint(implementation.interface, state);
    for (const auto &associated : implementation.associated) {
      out += associated.name;
      typeFingerprint(associated.value, state);
      typeFingerprint(associated.annotation, state);
    }
    out += ")\n";
  }
  for (const auto &interface : module.interfaces) {
    out += std::string("J(") + (interface.unsafeInterface ? "unsafe " : "") +
           interface.name;
    contextFingerprint(interface.nameContext, state);
    for (const auto &superinterface : interface.superinterfaces)
      typeFingerprint(superinterface, state);
    out += ")\n";
  }
  for (const auto &alias : module.aliases) {
    out += "A(" + alias.name;
    typeFingerprint(alias.target, state);
    out += ")\n";
  }
  for (const auto &item : module.imports) {
    out += "M(";
    for (const auto &component : item.path)
      out += component + '/';
    out += item.alias + (item.glob ? " *" : "");
    for (const auto &name : item.names)
      out += ' ' + name.name + '=' + name.alias;
    out += ")\n";
  }
  for (const auto &entry : module.statics) {
    out += "S(" + entry.name;
    typeFingerprint(entry.annotation, state);
    if (entry.initializer.get())
      nodeFingerprint(*entry.initializer, state);
    out += ")\n";
  }
  return out;
}
} // namespace mettle
