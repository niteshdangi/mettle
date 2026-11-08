// expect-exit: 0
// profiles: debug release
// Evidence for the value traits of the closure-free adapters: Clone produces an
// independent copy at the same position, and Default builds an adapter whose
// wrapped iterators are their own Default values. A small counting iterator
// with Clone and Default supplies the base type for the Default checks.

import core.clone.Clone
import core.default.Default
import core.iter
import core.iter.{Iterator}

type Ticks { at: i32; last: i32 }

extend Ticks implements Iterator {
    type Item = i32
    mut fn next(): i32? {
        if self.at >= self.last { return none }
        self.at = self.at + 1
        present(self.at)
    }
}

extend Ticks implements Clone {
    fn clone(): Ticks { Ticks(self.at, self.last) }
}

extend Ticks implements Default {
    static fn default(): Ticks { Ticks(0, 0) }
}

fn fresh<T: Default>(): T { T.(Default).default() }

fn checks_clone_positions(): i32 {
    var original = iter.range(0, 3).enumerate()
    if original.next() != present((0usize, 0)) { return 1 }
    var duplicate = original.clone()
    if duplicate.next() != present((1usize, 1)) { return 2 }
    if original.count() != 2usize || duplicate.count() != 1usize { return 3 }

    var limited = iter.range(0, 5).take_n(4usize)
    var limited_copy = limited.clone()
    if limited.next() != present(0) || limited_copy.next() != present(0) { return 4 }
    if limited.count() != 3usize || limited_copy.count() != 3usize { return 5 }

    var skipped = iter.range(0, 5).skip(2usize)
    var skipped_copy = skipped.clone()
    if skipped.next() != present(2) || skipped_copy.next() != present(2) { return 6 }

    var stepped = iter.range(0, 9).step_by(4usize)
    var stepped_copy = stepped.clone()
    if stepped.next() != present(0) || stepped_copy.next() != present(0) { return 7 }
    if stepped_copy.next() != present(4) || stepped.next() != present(4) { return 8 }

    var fused = iter.range(0, 1).fuse()
    var fused_copy = fused.clone()
    if fused.next() != present(0) || fused.next().is_present() { return 9 }
    if fused_copy.next() != present(0) { return 10 }

    var reversed = iter.range(0, 3).rev()
    var reversed_copy = reversed.clone()
    if reversed.next() != present(2) || reversed_copy.next() != present(2) { return 11 }

    var zipped = iter.range(0, 3).zip(iter.range(10, 12))
    var zipped_copy = zipped.clone()
    if zipped.next() != present((0, 10)) || zipped_copy.next() != present((0, 10)) { return 12 }

    var chained = iter.range(0, 1).chain(iter.range(5, 6))
    var chained_copy = chained.clone()
    if chained.next() != present(0) || chained.next() != present(5) { return 13 }
    if chained_copy.next() != present(0) || chained_copy.count() != 1usize { return 14 }
    0
}

fn checks_default_adapters(): i32 {
    var enumerated: iter.Enumerated<Ticks> = fresh()
    if enumerated.next().is_present() { return 20 }
    var limited: iter.Limited<Ticks> = fresh()
    if limited.count() != 0usize { return 21 }
    var skipped: iter.Skipped<Ticks> = fresh()
    if skipped.count() != 0usize { return 22 }
    var fused: iter.Fused<Ticks> = fresh()
    if fused.next().is_present() { return 23 }
    var zipped: iter.Zipped<Ticks, Ticks> = fresh()
    if zipped.count() != 0usize { return 26 }
    var chained: iter.Chained<Ticks, Ticks> = fresh()
    if chained.next().is_present() { return 27 }
    0
}

fn checks_default_then_clone(): i32 {
    var base: iter.Chained<Ticks, Ticks> = fresh()
    var base_copy = base.clone()
    if base_copy.next().is_present() { return 30 }
    0
}

fn main(): i32 {
    var code = checks_clone_positions()
    if code != 0 { return code }
    code = checks_default_adapters()
    if code != 0 { return code }
    checks_default_then_clone()
}
