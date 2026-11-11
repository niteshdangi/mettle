#include <stddef.h>
#include <stdint.h>

static size_t allocations;
static int measuring;

extern uint8_t *__real_mettle_rt_alloc(size_t size, size_t align);
extern uint8_t *__real_mettle_rt_realloc(uint8_t *pointer, size_t old_size,
                                         size_t align, size_t new_size);

void mettle_c_heap_global_begin(void) {
  allocations = 0;
  measuring = 1;
}

size_t mettle_c_heap_global_end(void) {
  measuring = 0;
  return allocations;
}

uint8_t *__wrap_mettle_rt_alloc(size_t size, size_t align) {
  if (measuring)
    ++allocations;
  return __real_mettle_rt_alloc(size, align);
}

uint8_t *__wrap_mettle_rt_realloc(uint8_t *pointer, size_t old_size,
                                  size_t align, size_t new_size) {
  if (measuring)
    ++allocations;
  return __real_mettle_rt_realloc(pointer, old_size, align, new_size);
}
