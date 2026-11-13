import alloc.arc
import alloc.rc
import core.default.Default

fn default_value<T: Default>(): T { T.(Default).default() }

fn main(): i32 {
    let local_empty = rc.new_weak<i32>()
    let local_default = default_value<rc.Weak<i32>>()
    if local_empty.strong_count() != 0usize || local_empty.weak_count() != 0usize ||
        local_default.strong_count() != 0usize ||
        local_default.weak_count() != 0usize {
        return 1
    }
    if local_empty.upgrade().is_present() || local_default.upgrade().is_present() {
        return 2
    }
    let local_raw = local_empty.retain().into_raw()
    let local_restored = unsafe { rc.weak_from_raw(local_raw) }
    if local_restored.strong_count() != 0usize ||
        local_restored.weak_count() != 0usize ||
        local_restored.upgrade().is_present() {
        return 3
    }

    let atomic = arc.new_weak<i32>()
    let atomic_default = default_value<arc.Weak<i32>>()
    if atomic.strong_count() != 0usize || atomic.weak_count() != 0usize ||
        atomic_default.strong_count() != 0usize ||
        atomic_default.weak_count() != 0usize {
        return 4
    }
    if atomic.upgrade().is_present() || atomic_default.upgrade().is_present() {
        return 5
    }
    let atomic_raw = atomic.retain().into_raw()
    let atomic_restored = unsafe { arc.weak_from_raw(atomic_raw) }
    if atomic_restored.strong_count() != 0usize ||
        atomic_restored.weak_count() != 0usize ||
        atomic_restored.upgrade().is_present() {
        return 6
    }
    0
}
