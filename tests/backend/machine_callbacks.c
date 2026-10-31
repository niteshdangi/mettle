#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#if defined(__aarch64__)
#include <arm_neon.h>
#endif

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
struct MettleDarwinHfa3 {
  double first;
  double second;
  double third;
};
struct MettleDarwinHfa1 {
  double first;
};
struct MettleDarwinHfa2 {
  double first;
  double second;
};
struct MettleDarwinHfa4 {
  double first;
  double second;
  double third;
  double fourth;
};
struct MettleDarwinHva2 {
  MettleMachineVector first;
  MettleMachineVector second;
};
struct MettleDarwinHva1 {
  MettleMachineVector first;
};
struct MettleDarwinHva3 {
  MettleMachineVector first;
  MettleMachineVector second;
  MettleMachineVector third;
};
struct MettleDarwinHva4 {
  MettleMachineVector first;
  MettleMachineVector second;
  MettleMachineVector third;
  MettleMachineVector fourth;
};
struct MettleDarwinLayoutLeaf {
  uint8_t tag;
  uint64_t value;
};
struct __attribute__((aligned(32))) MettleDarwinLayout {
  uint8_t prefix;
  struct MettleDarwinLayoutLeaf leaf;
  uint32_t tail;
};
struct __attribute__((packed)) MettleDarwinPacked {
  uint8_t tag;
  uint32_t payload;
};
union MettleDarwinLayoutUnion {
  int64_t integer;
  double real;
};
struct MettleDarwinLayoutTagged {
  int32_t tag;
  union {
    int64_t integer;
    double real;
  } payload;
};
struct MettleDarwinHfa3 mettle_c_darwin_hfa(struct MettleDarwinHfa3 value) {
  value.first += 1.0;
  value.second += 1.0;
  value.third += 1.0;
  return value;
}
struct MettleDarwinHfa1 mettle_c_darwin_hfa1(struct MettleDarwinHfa1 value) {
  value.first += 1.0;
  return value;
}
struct MettleDarwinHfa2 mettle_c_darwin_hfa2(struct MettleDarwinHfa2 value) {
  value.first += 1.0;
  value.second += 1.0;
  return value;
}
struct MettleDarwinHfa4 mettle_c_darwin_hfa4(struct MettleDarwinHfa4 value) {
  value.first += 1.0;
  value.second += 1.0;
  value.third += 1.0;
  value.fourth += 1.0;
  return value;
}
struct MettleDarwinHfa1 mettle_c_darwin_hfa1_callback(
    struct MettleDarwinHfa1 (*callback)(struct MettleDarwinHfa1),
    struct MettleDarwinHfa1 value) {
  return callback(value);
}
struct MettleDarwinHva4 mettle_c_darwin_hva4_callback(
    struct MettleDarwinHva4 (*callback)(struct MettleDarwinHva4),
    struct MettleDarwinHva4 value) {
  return callback(value);
}
struct MettleDarwinHfa3 mettle_c_darwin_hfa_callback(
    struct MettleDarwinHfa3 (*callback)(struct MettleDarwinHfa3),
    struct MettleDarwinHfa3 value) {
  return callback(value);
}
struct MettleDarwinHva2 mettle_c_darwin_hva(struct MettleDarwinHva2 value) {
  value.first += (MettleMachineVector){1, 1, 1, 1};
  value.second += (MettleMachineVector){2, 2, 2, 2};
  return value;
}
struct MettleDarwinHva1 mettle_c_darwin_hva1(struct MettleDarwinHva1 value) {
  value.first += (MettleMachineVector){1, 1, 1, 1};
  return value;
}
struct MettleDarwinHva3 mettle_c_darwin_hva3(struct MettleDarwinHva3 value) {
  value.first += (MettleMachineVector){1, 1, 1, 1};
  value.second += (MettleMachineVector){2, 2, 2, 2};
  value.third += (MettleMachineVector){3, 3, 3, 3};
  return value;
}
struct MettleDarwinHva4 mettle_c_darwin_hva4(struct MettleDarwinHva4 value) {
  value.first += (MettleMachineVector){1, 1, 1, 1};
  value.second += (MettleMachineVector){2, 2, 2, 2};
  value.third += (MettleMachineVector){3, 3, 3, 3};
  value.fourth += (MettleMachineVector){4, 4, 4, 4};
  return value;
}
struct MettleDarwinHva2 mettle_c_darwin_hva_callback(
    struct MettleDarwinHva2 (*callback)(struct MettleDarwinHva2),
    struct MettleDarwinHva2 value) {
  return callback(value);
}
int32_t mettle_c_darwin_large_callback(
    struct MettleLarge (*callback)(struct MettleLarge)) {
  struct MettleLarge value = {10, 12, 20};
  struct MettleLarge result = callback(value);
  return result.first == 11 && result.second == 13 && result.third == 21;
}
int32_t mettle_c_darwin_variadic(int32_t count, ...) {
  va_list arguments;
  va_start(arguments, count);
  // HVA precedes HFA: Apple clang's caller and va_arg disagree on HVA
  // alignment directly after a 24-byte HFA, so C itself cannot round-trip it.
  struct MettleDarwinHva2 hva = va_arg(arguments, struct MettleDarwinHva2);
  struct MettleDarwinHfa3 hfa = va_arg(arguments, struct MettleDarwinHfa3);
  struct MettleLarge large = va_arg(arguments, struct MettleLarge);
  va_end(arguments);
  return count == 3 && hfa.first == 1.0 && hfa.second == 2.0 &&
         hfa.third == 3.0 && hva.first[0] == 4 && hva.second[3] == 5 &&
         large.first == 10 && large.second == 12 && large.third == 20;
}
int32_t mettle_c_darwin_variadic_definition(int32_t (*callback)(int32_t, ...)) {
  struct MettleDarwinHfa3 hfa = {1.0, 2.0, 3.0};
  struct MettleDarwinHva2 hva = {(MettleMachineVector){4, 4, 4, 4},
                                 (MettleMachineVector){5, 5, 5, 5}};
  struct MettleLarge large = {10, 12, 20};
  return callback(3, hva, hfa, large);
}
int32_t mettle_c_darwin_layout_metrics(size_t size, size_t alignment,
                                       size_t leaf_offset, size_t value_offset,
                                       size_t tail_offset) {
  return size == sizeof(struct MettleDarwinLayout) &&
         alignment == _Alignof(struct MettleDarwinLayout) &&
         leaf_offset == offsetof(struct MettleDarwinLayout, leaf) &&
         value_offset == offsetof(struct MettleDarwinLayout, leaf) +
                             offsetof(struct MettleDarwinLayoutLeaf, value) &&
         tail_offset == offsetof(struct MettleDarwinLayout, tail);
}
struct MettleDarwinPacked
mettle_c_darwin_packed_echo(struct MettleDarwinPacked value) {
  value.payload += 1;
  return value;
}
int32_t mettle_c_darwin_layout_extra_metrics(
    size_t union_size, size_t union_alignment, size_t tagged_size,
    size_t tagged_alignment, size_t transparent_size,
    size_t transparent_alignment) {
  return union_size == sizeof(union MettleDarwinLayoutUnion) &&
         union_alignment == _Alignof(union MettleDarwinLayoutUnion) &&
         tagged_size == sizeof(struct MettleDarwinLayoutTagged) &&
         tagged_alignment == _Alignof(struct MettleDarwinLayoutTagged) &&
         offsetof(struct MettleDarwinLayoutTagged, tag) == 0 &&
         offsetof(struct MettleDarwinLayoutTagged, payload) ==
             _Alignof(union MettleDarwinLayoutUnion) &&
         transparent_size == sizeof(uint64_t) &&
         transparent_alignment == _Alignof(uint64_t);
}
union MettleDarwinLayoutUnion
mettle_c_darwin_layout_union(union MettleDarwinLayoutUnion value) {
  value.integer += 1;
  return value;
}
struct MettleDarwinLayoutTagged
mettle_c_darwin_layout_tagged(struct MettleDarwinLayoutTagged value) {
  if (value.tag == 7)
    value.payload.integer += 1;
  return value;
}
uint64_t mettle_c_darwin_layout_transparent(uint64_t value) {
  return value + 1;
}
_Bool mettle_c_darwin_bool_roundtrip(_Bool value) { return value; }
_Bool mettle_c_darwin_bool_callback(_Bool (*callback)(_Bool), _Bool value) {
  return callback(value);
}
// Mettle `char` is a Unicode scalar passed as uint32_t (char32_t).
uint32_t mettle_c_darwin_char_next(uint32_t value) { return value + 1; }
uint32_t mettle_c_darwin_char_callback(uint32_t (*callback)(uint32_t),
                                       uint32_t value) {
  return callback(value) == 0x1F601u ? 0x10FFFFu : 0;
}
int32_t mettle_c_darwin_variadic_float_definition(
    int32_t (*callback)(int32_t, ...)) {
  return callback(1, (float)42.0f);
}
#if defined(METTLE_DARWIN_PROBE)
extern int32_t mettle_darwin_exported_increment(int32_t);
int32_t mettle_c_darwin_exported_call(int32_t value) {
  return mettle_darwin_exported_increment(value);
}
#endif
int32_t mettle_c_darwin_asm_call(int32_t (*callback)(int32_t, int32_t),
                                 int32_t left, int32_t right) {
  return callback(left, right);
}
int32_t
mettle_c_darwin_volatile_observe(int32_t (*callback)(volatile int32_t *)) {
  volatile int32_t value = 40;
  int32_t before = callback(&value);
  return before == 41 && value == 42 ? 42 : -1;
}
#if defined(__aarch64__)
void mettle_c_darwin_neon_transform(const int32_t *left, const int32_t *right,
                                    int32_t *output) {
  int32x4_t first = vld1q_s32(left);
  int32x4_t second = vld1q_s32(right);
  vst1q_s32(output, vaddq_s32(first, second));
}
#endif
struct MettleAlignedWide {
  __int128 value;
};
int32_t mettle_c_aligned_wide_stack(int64_t a, int64_t b, int64_t c, int64_t d,
                                    int64_t e, int64_t f, int64_t g, int64_t h,
                                    int32_t marker,
                                    struct MettleAlignedWide q) {
  return a + b + c + d + e + f + g + h == 36 && marker == 9 && q.value == 77;
}
int32_t mettle_c_aligned_wide_callback(
    int32_t (*callback)(int64_t, int64_t, int64_t, int64_t, int64_t, int64_t,
                        int64_t, int64_t, int32_t, struct MettleAlignedWide)) {
  return callback(1, 2, 3, 4, 5, 6, 7, 8, 9, (struct MettleAlignedWide){77});
}
int32_t mettle_c_aligned_wide_varargs(int32_t first, ...) {
  va_list arguments;
  va_start(arguments, first);
  int32_t marker = va_arg(arguments, int);
  struct MettleAlignedWide q = va_arg(arguments, struct MettleAlignedWide);
  int32_t tail = va_arg(arguments, int);
  va_end(arguments);
  return first == 1 && marker == 5 && q.value == 77 && tail == 6;
}
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
