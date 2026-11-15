// profiles: debug release
import core.cmp.Eq
import std.panic.BacktraceStatus

fn require_eq<T: Eq>(read value: T): bool { value == value }

fn main(): i32 {
    if BacktraceStatus.Captured == BacktraceStatus.Disabled { return 1 }
    if BacktraceStatus.Disabled == BacktraceStatus.Unsupported { return 2 }
    if BacktraceStatus.Unsupported != BacktraceStatus.Unsupported { return 3 }
    if !require_eq(BacktraceStatus.Captured) { return 4 }
    0
}
