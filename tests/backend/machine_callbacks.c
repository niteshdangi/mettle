#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>

int32_t mettle_c_machine_answer(void) { return 42; }
int32_t mettle_c_machine_binary(int32_t (*callback)(int32_t, int32_t)) {
  return callback(20, 22);
}
int32_t mettle_c_machine_stack(int32_t (*callback)(int32_t, int32_t, int32_t,
                                                   int32_t, int32_t, int32_t,
                                                   int32_t, int32_t, int32_t,
                                                   int32_t)) {
  return callback(1, 2, 3, 4, 5, 6, 7, 8, 9, 41);
}
typedef int32_t MettleMachineVector __attribute__((vector_size(16)));
typedef int64_t MettleMachineWideVector __attribute__((vector_size(16)));
struct MettleMachineVectorPair {
  MettleMachineVector first;
  MettleMachineWideVector second;
};
union MettleMachineVectorUnion {
  MettleMachineVector vector;
  double floating;
  uint64_t integer;
};
struct MettleMachineVectorPair
mettle_c_machine_vector_pair(struct MettleMachineVectorPair value) {
  value.first += (MettleMachineVector){1, 1, 1, 1};
  value.second += (MettleMachineWideVector){2, 2};
  return value;
}
union MettleMachineVectorUnion
mettle_c_machine_vector_union(union MettleMachineVectorUnion value) {
  value.vector += (MettleMachineVector){1, 1, 1, 1};
  return value;
}
#if defined(__x86_64__)
typedef int32_t MettleMachineVector256 __attribute__((vector_size(32)));
struct MettleMachineScalarFloat {
  double value;
};
__attribute__((target("avx"))) double
mettle_c_machine_vector_variadic(int count, ...) {
  va_list arguments;
  va_start(arguments, count);
  MettleMachineVector256 vector = va_arg(arguments, MettleMachineVector256);
  double result = vector[0];
  for (int i = 0; i < count; ++i)
    result += va_arg(arguments, double);
  struct MettleMachineScalarFloat last =
      va_arg(arguments, struct MettleMachineScalarFloat);
  va_end(arguments);
  return result + last.value;
}
#endif
MettleMachineVector mettle_c_machine_vector(MettleMachineVector value) {
  return value + (MettleMachineVector){1, 1, 1, 1};
}
int32_t mettle_c_machine_vector_definition(int32_t (*callback)(int32_t, ...)) {
  MettleMachineVector value = {42, 42, 42, 42};
  return callback(1, value, 2, 40.0);
}
MettleMachineVector mettle_c_machine_vector_callback(
    MettleMachineVector (*callback)(MettleMachineVector),
    MettleMachineVector value) {
  return callback(value);
}

static int32_t mettle_zst_drops;
void mettle_c_zst_reset(void) { mettle_zst_drops = 0; }
void mettle_c_zst_drop(void) { ++mettle_zst_drops; }
int32_t mettle_c_zst_count(void) { return mettle_zst_drops; }

struct MettlePair {
  int32_t first;
  int32_t second;
};
struct MettleFloats {
  float first;
  float second;
};
struct MettleMixed {
  double first;
  int32_t second;
};
struct MettleLarge {
  int64_t first;
  int64_t second;
  int64_t third;
};
struct __attribute__((packed)) MettlePacked {
  uint8_t first;
  int32_t second;
};
int32_t mettle_c_static_storage(const int32_t *value, int32_t *count) {
  *count += *value - 1;
  return *value;
}
int32_t mettle_c_variadic_definition_scalars(int32_t (*callback)(int32_t,
                                                                 ...)) {
  return callback(2, 20, 22);
}
int32_t mettle_c_variadic_definition_aggregates(int32_t (*callback)(int32_t,
                                                                    ...)) {
  struct MettleMixed mixed = {20.0, 22};
  struct MettlePair pair = {20, 22};
  struct MettleFloats floats = {20.0f, 22.0f};
  struct MettleLarge large = {10, 12, 20};
  struct MettlePacked packed = {20, 22};
  return callback(1, mixed, INT64_C(1), INT64_C(2), INT64_C(3), INT64_C(4),
                  INT64_C(5), INT64_C(6), INT64_C(7), INT64_C(8), INT64_C(9),
                  INT64_C(10), pair, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0,
                  9.0, 10.0, floats, large, packed);
}
int32_t mettle_c_variadic_definition_wide(int32_t (*callback)(int32_t, ...)) {
  struct Triple {
    double first, second, third;
  } triple = {10.0, 12.0, 20.0};
  __int128 wide = ((__int128)1 << 100) + 42;
  return callback(1, triple, wide, 42);
}
struct MettleTagged {
  int32_t tag;
  union {
    int64_t integer;
    double real;
  } payload;
};
struct MettleTinyTagged {
  uint8_t tag;
  union {
    uint8_t byte;
    uint64_t wide;
  } payload;
};
struct MettleTinyTagged mettle_c_tiny_tagged(struct MettleTinyTagged value) {
  if (value.tag == 9)
    value.payload.byte += 1;
  return value;
}
int8_t mettle_c_transparent_callback(int8_t (*callback)(int8_t), int8_t value) {
  return callback(value);
}
double mettle_c_transparent_double(double value) { return value + 1.0; }
union MettleUnion {
  int64_t integer;
  double real;
};
union MettleDoubleUnion {
  double first;
  double second;
};
union MettleUnion mettle_c_union(union MettleUnion value) {
  value.integer += 1;
  return value;
}
union MettleDoubleUnion mettle_c_double_union(union MettleDoubleUnion value,
                                              double increment) {
  value.first += increment;
  return value;
}
struct MettleTagged mettle_c_tagged(struct MettleTagged value) {
  if (value.tag == 7)
    value.payload.integer += 1;
  if (value.tag == 11)
    value.payload.real += 1.0;
  return value;
}
size_t mettle_c_tagged_size(void) { return sizeof(struct MettleTagged); }
uint8_t mettle_c_byte_enum(uint8_t value) { return value + 1; }
int32_t mettle_c_enum_variadic(int count, ...) {
  va_list arguments;
  va_start(arguments, count);
  int32_t result = 0;
  for (int i = 0; i < count; ++i)
    result += va_arg(arguments, int);
  va_end(arguments);
  return result;
}

int64_t mettle_c_integer(int8_t first, uint8_t second, int64_t third) {
  return first + second + third;
}
struct MettlePair mettle_c_pair(struct MettlePair value) {
  value.first += 1;
  value.second += 1;
  return value;
}
extern struct MettlePair mettle_export_pair(struct MettlePair value);
struct MettlePair mettle_c_call_export(struct MettlePair value) {
  return mettle_export_pair(value);
}
struct MettleFloats mettle_c_floats(struct MettleFloats value) {
  value.first += 1.0f;
  value.second += 1.0f;
  return value;
}
struct MettleMixed mettle_c_mixed(struct MettleMixed value) {
  value.first += 1.0;
  value.second += 1;
  return value;
}
struct MettleLarge mettle_c_large(struct MettleLarge value) {
  value.first += 1;
  value.second += 1;
  value.third += 1;
  return value;
}
struct MettlePacked mettle_c_packed(struct MettlePacked value) {
  value.first += 1;
  value.second += 1;
  return value;
}
double mettle_c_variadic(int count, ...) {
  va_list arguments;
  va_start(arguments, count);
  double result = 0.0;
  for (int i = 0; i < count; ++i)
    result += va_arg(arguments, double);
  va_end(arguments);
  return result;
}
int32_t mettle_c_callback(int32_t (*callback)(void *, int32_t), void *context,
                          int32_t value) {
  return callback(context, value);
}
size_t mettle_c_pair_size(void) { return sizeof(struct MettlePair); }
size_t mettle_c_packed_offset(void) {
  return offsetof(struct MettlePacked, second);
}
