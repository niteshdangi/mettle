p="bootstrap/semantics/interfaces.h"
s=open(p).read()
old="  std::size_t declaration = static_cast<std::size_t>(-1);\n};\nstruct Projection {"
new="  std::size_t declaration = static_cast<std::size_t>(-1);\n  // Mounted from a checked library, whose coherence was proven when it was\n  // built; only pairs involving the program's own implementations are new.\n  bool checkedImport = false;\n};\nstruct Projection {"
assert old in s
open(p,"w").write(s.replace(old,new,1))
p="bootstrap/semantics/interface_implementations.cpp"
s=open(p).read()
old="    implementation.declaration = i;\n    implementation.span = syntax.span;\n"
new="    implementation.declaration = i;\n    implementation.checkedImport = syntax.item.checkedImport;\n    implementation.span = syntax.span;\n"
assert old in s
open(p,"w").write(s.replace(old,new,1))
p="bootstrap/semantics/coherence.cpp"
s=open(p).read()
old="  for (std::size_t i = 0; i < database.implementations.size(); ++i) {\n    const auto &left = database.implementations[i];\n    std::set<Type> known;"
new="  for (std::size_t i = 0; i < database.implementations.size(); ++i) {\n    const auto &left = database.implementations[i];\n    if (left.checkedImport) {\n      for (std::size_t j = 0; j < i; ++j)\n        if (!database.implementations[j].checkedImport)\n          overlaps(left, database.implementations[j], valid);\n      continue;\n    }\n    std::set<Type> known;"
open(p+".bak","w").write(s)
