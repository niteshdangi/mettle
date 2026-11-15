import core.char
import core.iter.{FusedIterator, Iterator}

fn is_fused<I: FusedIterator>(mut iterator: I): bool {
    while iterator.next().is_present() {}
    !iterator.next().is_present()
}

fn main(): i32 {
    if is_fused('\n'.escape_default()) { 0 } else { 1 }
}
