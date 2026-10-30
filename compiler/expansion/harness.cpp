#include "expansion/harness.h"

namespace mettle::expansion {
namespace {
std::string call(const Module::TestFunction &entry) {
  std::string path;
  for (const auto &part : entry.path)
    path += (path.empty() ? "" : "::") + part;
  return path + "()";
}

const char *digits = R"(fn mettle_harness_digit(value: u64): Unit {
    if value == 0u64 { std::io::print("0") }
    if value == 1u64 { std::io::print("1") }
    if value == 2u64 { std::io::print("2") }
    if value == 3u64 { std::io::print("3") }
    if value == 4u64 { std::io::print("4") }
    if value == 5u64 { std::io::print("5") }
    if value == 6u64 { std::io::print("6") }
    if value == 7u64 { std::io::print("7") }
    if value == 8u64 { std::io::print("8") }
    if value == 9u64 { std::io::print("9") }
}
fn mettle_harness_number(value: u64): Unit {
    if value >= 10u64 { mettle_harness_number(value / 10u64) }
    mettle_harness_digit(value % 10u64)
}
)";
} // namespace

std::string harnessSource(const std::vector<Module::TestFunction> &tests,
                          bool bench) {
  std::string text = "\n";
  if (bench)
    text += digits;
  for (std::size_t i = 0; i < tests.size(); ++i) {
    const auto &entry = tests[i];
    if (entry.bench != bench)
      continue;
    auto index = std::to_string(i);
    if (!bench) {
      text += "fn mettle_harness_run_" + index + "(): i32 {\n";
      if (entry.fallible)
        text += "    let outcome = capture " + call(entry) +
                "\n    if outcome.is_success() { 0 } else { " +
                std::to_string(harnessFailureStatus) + " }\n}\n";
      else
        text += "    " + call(entry) + "\n    0\n}\n";
      continue;
    }
    text += "fn mettle_harness_sample_" + index +
            "(iterations: u64): u64 {\n"
            "    let start = std::time::now()\n"
            "    var count = 0u64\n"
            "    while count < iterations {\n";
    // The result goes through `black_box`, so a benchmark that returns its
    // work is measured instead of folded away.
    text += entry.fallible
                ? "        let outcome = core::hint::black_box(capture " +
                      call(entry) + ")\n"
                : "        let result = core::hint::black_box(" + call(entry) +
                      ")\n";
    text += "        count += 1u64\n"
            "    }\n"
            "    start.elapsed().as_nanos() as u64\n"
            "}\n"
            "fn mettle_harness_run_" +
            index +
            "(): i32 {\n"
            "    var iterations = 1u64\n"
            "    var total = mettle_harness_sample_" +
            index +
            "(iterations)\n"
            "    while total < 10000000u64 && iterations < 1000000000000u64 {\n"
            "        iterations *= 2u64\n"
            "        total = mettle_harness_sample_" +
            index +
            "(iterations)\n"
            "    }\n"
            "    mettle_harness_number(iterations)\n"
            "    var sample = 0u32\n"
            "    while sample < " +
            std::to_string(harnessBenchSamples) +
            "u32 {\n"
            "        std::io::print(\" \")\n"
            "        mettle_harness_number(mettle_harness_sample_" +
            index +
            "(iterations))\n"
            "        sample += 1u32\n"
            "    }\n"
            "    std::io::print(\"\\n\")\n"
            "    0\n"
            "}\n";
  }
  const auto usage = std::to_string(harnessUsageStatus);
  text += "fn main(): i32 {\n"
          "    let args = std::env::args()\n"
          "    if args.len() != 3usize { return " +
          usage +
          " }\n"
          "    if !args[1usize].as_os_str().same("
          "std::ffi::os_str_from_text(\"";
  text += bench ? harnessBenchSelector : harnessTestSelector;
  text += "\")) { return " + usage + " }\n";
  for (std::size_t i = 0; i < tests.size(); ++i)
    if (tests[i].bench == bench) {
      auto index = std::to_string(i);
      text += "    if args[2usize].as_os_str().same("
              "std::ffi::os_str_from_text(\"" +
              index + "\")) { return mettle_harness_run_" + index + "() }\n";
    }
  text += "    " + usage + "\n}\n";
  return text;
}
} // namespace mettle::expansion
