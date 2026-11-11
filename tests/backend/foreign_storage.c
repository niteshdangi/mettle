#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>

struct MettleSnapshotBytes {
  uint8_t data[1025];
};
struct MettleSnapshotWords {
  uint64_t data[129];
};

struct MettleSnapshotBytes
mettle_c_snapshot_bytes(struct MettleSnapshotBytes value) {
  for (size_t i = 0; i < 1025; ++i)
    value.data[i] = (uint8_t)(value.data[i] + i % 5 + 1);
  return value;
}

struct MettleSnapshotWords
mettle_c_snapshot_words(struct MettleSnapshotWords value) {
  for (size_t i = 0; i < 129; ++i)
    value.data[i] += i % 7 + 1;
  return value;
}

struct MettleSnapshotBytes
mettle_c_snapshot_wrapped(struct MettleSnapshotBytes value) {
  return mettle_c_snapshot_bytes(value);
}

struct MettleSnapshotBytes mettle_c_snapshot_variadic_bytes(int32_t count,
                                                            ...) {
  va_list arguments;
  va_start(arguments, count);
  struct MettleSnapshotBytes value =
      va_arg(arguments, struct MettleSnapshotBytes);
  va_end(arguments);
  if (count != 1)
    value.data[1024] = 255;
  return mettle_c_snapshot_bytes(value);
}

int32_t mettle_c_snapshot_bytes_callback(
    struct MettleSnapshotBytes (*callback)(struct MettleSnapshotBytes),
    struct MettleSnapshotBytes value) {
  struct MettleSnapshotBytes expected = mettle_c_snapshot_bytes(value);
  struct MettleSnapshotBytes observed = callback(value);
  for (size_t i = 0; i < 1025; ++i)
    if (observed.data[i] != expected.data[i])
      return 0;
  return 1;
}

int32_t mettle_c_snapshot_words_callback(
    struct MettleSnapshotWords (*callback)(struct MettleSnapshotWords),
    struct MettleSnapshotWords value) {
  struct MettleSnapshotWords expected = mettle_c_snapshot_words(value);
  struct MettleSnapshotWords observed = callback(value);
  for (size_t i = 0; i < 129; ++i)
    if (observed.data[i] != expected.data[i])
      return 0;
  return 1;
}

extern struct MettleSnapshotBytes
mettle_snapshot_export_bytes(struct MettleSnapshotBytes value);
extern struct MettleSnapshotWords
mettle_snapshot_export_words(struct MettleSnapshotWords value);
extern struct MettleSnapshotBytes mettle_snapshot_export_variadic(int32_t count,
                                                                  ...);

int32_t mettle_c_snapshot_exports(void) {
  struct MettleSnapshotBytes bytes;
  struct MettleSnapshotWords words;
  for (size_t i = 0; i < 1025; ++i)
    bytes.data[i] = (uint8_t)(i % 31);
  for (size_t i = 0; i < 129; ++i)
    words.data[i] = (uint64_t)i * 17 + 2;
  struct MettleSnapshotBytes direct = mettle_snapshot_export_bytes(bytes);
  struct MettleSnapshotWords aligned = mettle_snapshot_export_words(words);
  struct MettleSnapshotBytes variadic =
      mettle_snapshot_export_variadic(1, bytes);
  for (size_t i = 0; i < 1025; ++i) {
    uint8_t original = (uint8_t)(i % 31);
    uint8_t expected = (uint8_t)(original + i % 5 + 1);
    if (bytes.data[i] != original || direct.data[i] != expected ||
        variadic.data[i] != expected)
      return 0;
  }
  for (size_t i = 0; i < 129; ++i) {
    uint64_t original = (uint64_t)i * 17 + 2;
    if (words.data[i] != original || aligned.data[i] != original + i % 7 + 1)
      return 0;
  }
  return 1;
}
