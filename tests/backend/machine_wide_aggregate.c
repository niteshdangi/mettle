#include <stdarg.h>
#include <stdint.h>

typedef int32_t MettleMachineVector256 __attribute__((vector_size(32)));
struct MettleMachineWideAggregate {
  MettleMachineVector256 value;
};

struct MettleMachineWideAggregate
mettle_c_machine_wide_aggregate(struct MettleMachineWideAggregate value) {
  value.value += (MettleMachineVector256){1, 1, 1, 1, 1, 1, 1, 1};
  return value;
}

extern struct MettleMachineWideAggregate
    mettle_wide_aggregate_identity(struct MettleMachineWideAggregate);

struct MettleMachineWideAggregate
mettle_c_machine_wide_callback(struct MettleMachineWideAggregate value) {
  return mettle_wide_aggregate_identity(value);
}

double mettle_c_machine_wide_variadic(int count, ...) {
  va_list arguments;
  va_start(arguments, count);
  struct MettleMachineWideAggregate value =
      va_arg(arguments, struct MettleMachineWideAggregate);
  double result = value.value[0];
  for (int i = 0; i < count; ++i)
    result += va_arg(arguments, double);
  struct ScalarFloat {
    double value;
  };
  result += va_arg(arguments, struct ScalarFloat).value;
  va_end(arguments);
  return result;
}
