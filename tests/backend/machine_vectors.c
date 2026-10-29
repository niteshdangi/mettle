#include <stdint.h>

typedef int32_t MettleMachineVector256 __attribute__((vector_size(32)));

MettleMachineVector256
mettle_c_machine_vector256(MettleMachineVector256 value) {
  return value + (MettleMachineVector256){1, 1, 1, 1, 1, 1, 1, 1};
}
