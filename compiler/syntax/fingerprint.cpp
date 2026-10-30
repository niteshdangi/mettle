#include "syntax/fingerprint.h"

namespace mettle {
namespace {
void typeFingerprint(const TypeSyntax &type, std::string &out);
void nodeFingerprint(const Node &node, std::string &out);

void patternFingerprint(const Pattern &pattern, std::string &out) {
  out += "P(" + std::to_string(static_cast<int>(pattern.kind)) + ' ' +
         pattern.text + ' ' + pattern.field;
  for (const auto &child : pattern.children)
    patternFingerprint(child, out);
  out += ')';
}
void argumentsFingerprint(const std::vector<GenericArgument> &arguments,
                          std::string &out) {
  out += '<';
  for (const auto &argument : arguments) {
    out += argument.binding + '=' + argument.region;
    if (argument.type)
      typeFingerprint(*argument.type, out);
    if (argument.value)
      nodeFingerprint(*argument.value, out);
    out += ',';
  }
  out += '>';
}
void typeFingerprint(const TypeSyntax &type, std::string &out) {
  out += "T(" + std::to_string(static_cast<int>(type.form)) + ' ' + type.view +
         ' ' + type.name;
  for (const auto &source : type.sources)
    out += " from " + source;
  for (const auto &region : type.regions)
    out += " region " + region;
  for (const auto &binder : type.binders)
    out += " for " + binder;
  if (type.nested)
    typeFingerprint(*type.nested, out);
  for (const auto &element : type.elements)
    typeFingerprint(element, out);
  argumentsFingerprint(type.arguments, out);
  if (type.countExpression)
    nodeFingerprint(*type.countExpression, out);
  if (type.callable) {
    const auto &callable = *type.callable;
    out += " callable " + callable.mode + ' ' + callable.abi;
    for (const auto &parameter : callable.parameters) {
      out += parameter.mode + ' ';
      typeFingerprint(parameter.annotation, out);
    }
    typeFingerprint(callable.result, out);
    typeFingerprint(callable.error, out);
  }
  out += ')';
}
void nodeFingerprint(const Node &node, std::string &out) {
  out += "K(" + std::to_string(static_cast<int>(node.kind)) + ' ' + node.text +
         ' ' + node.name + ' ' + node.label + (node.flag ? " 1" : " 0") +
         (node.semicolon ? ";" : "");
  typeFingerprint(node.annotation, out);
  typeFingerprint(node.error, out);
  for (const auto &pattern : node.patterns)
    patternFingerprint(pattern, out);
  for (const auto &parameter : node.parameters) {
    out += parameter.name + ':' + parameter.mode;
    typeFingerprint(parameter.annotation, out);
    if (parameter.pattern)
      patternFingerprint(*parameter.pattern, out);
  }
  argumentsFingerprint(node.ownerGenericArguments, out);
  argumentsFingerprint(node.genericArguments, out);
  for (const auto &child : node.children)
    nodeFingerprint(*child, out);
  out += ')';
}
} // namespace

std::string fingerprint(const Module &module) {
  std::string out;
  for (const auto &function : module.functions) {
    out += "F(" + function.name + ' ' + function.receiver + ' ' +
           function.owner + ' ';
    for (const auto &parameter : function.parameters) {
      out += parameter.name + ':' + parameter.mode + ' ';
      typeFingerprint(parameter.annotation, out);
      if (parameter.pattern)
        patternFingerprint(*parameter.pattern, out);
      if (parameter.defaultValue.get())
        nodeFingerprint(*parameter.defaultValue, out);
    }
    typeFingerprint(function.annotation, out);
    typeFingerprint(function.error, out);
    for (const auto &generic : function.genericParameters) {
      out += generic.name;
      for (const auto &bound : generic.bounds)
        typeFingerprint(bound, out);
    }
    for (const auto &constraint : function.constraints) {
      typeFingerprint(constraint.subject, out);
      for (const auto &bound : constraint.bounds)
        typeFingerprint(bound, out);
      if (constraint.equality)
        typeFingerprint(*constraint.equality, out);
    }
    if (function.body.get())
      nodeFingerprint(*function.body, out);
    out += ")\n";
  }
  for (const auto &product : module.products) {
    out += "D(" + product.name;
    for (const auto &field : product.fields) {
      out += ' ' + field.name;
      typeFingerprint(field.annotation, out);
    }
    for (const auto &variant : product.variants) {
      out += " variant " + variant.name;
      for (const auto &field : variant.fields)
        typeFingerprint(field.annotation, out);
    }
    for (const auto &interface : product.interfaces)
      typeFingerprint(interface, out);
    out += ")\n";
  }
  for (const auto &implementation : module.implementations) {
    out += std::string("I(") + (implementation.negative ? "not " : "") +
           (implementation.unsafeImplementation ? "unsafe " : "") +
           (implementation.shorthand ? "shorthand " : "");
    typeFingerprint(implementation.target, out);
    typeFingerprint(implementation.interface, out);
    for (const auto &associated : implementation.associated) {
      out += associated.name;
      typeFingerprint(associated.value, out);
      typeFingerprint(associated.annotation, out);
    }
    out += ")\n";
  }
  for (const auto &interface : module.interfaces) {
    out += "J(" + interface.name;
    for (const auto &superinterface : interface.superinterfaces)
      typeFingerprint(superinterface, out);
    out += ")\n";
  }
  for (const auto &alias : module.aliases) {
    out += "A(" + alias.name;
    typeFingerprint(alias.target, out);
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
    typeFingerprint(entry.annotation, out);
    if (entry.initializer.get())
      nodeFingerprint(*entry.initializer, out);
    out += ")\n";
  }
  return out;
}
} // namespace mettle
