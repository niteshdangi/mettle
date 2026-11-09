// profiles: debug release
import core.cmp.{Ord, Ordering, Reverse, min, max, clamp}
import core.default.Default
import core.fmt
import core.fmt.Debug
import core.hash.{BuildHasher, Fnv1a, Hash, Hasher, fnv1a}
import core.text.Text

type FnvFactory {}
extend FnvFactory implements BuildHasher {
    type Hasher = Fnv1a
    fn build_hasher(): Fnv1a { fnv1a() }
}

fn debug_is<T: Debug>(value: read T, expected: read Text): bool {
    var storage = [0u8; 200]
    var writer = fmt.buffer_writer(mut storage)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let written = writer.len()
    match fmt.written_text(read storage, written) {
        present(actual) => actual == expected,
        none => false
    }
}

fn make<T: Default>(): T { T.(Default).default() }

fn main(): i32 {
    if 3i32.max(7i32) != 7 || 3i32.min(7i32) != 3 { return 1 }
    if 4i32.clamp(1i32, 3i32) != 3 || 0i32.clamp(1i32, 3i32) != 1 || 2i32.clamp(1i32, 3i32) != 2 { return 2 }
    if max(4i32, 9i32) != 9 || min(4i32, 9i32) != 4 || clamp(8i32, 0i32, 5i32) != 5 { return 3 }
    let low = Reverse(1i32)
    let high = Reverse(2i32)
    if low.cmp(read high) != Ordering.Greater { return 4 }
    let top: Reverse<i32> = make()
    let five = Reverse(5i32)
    if top.value != 0 { return 5 }
    if !debug_is(read five, "Reverse(5)") { return 13 }

    var hashes = FnvFactory()
    let one = hashes.hash_one(read 42i32)
    var direct = fnv1a()
    42i32.hash(mut direct)
    if one != direct.finish() { return 6 }
    0
}
