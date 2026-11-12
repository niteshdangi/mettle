import alloc.{arc, boxed, rc}
import alloc.alloc.{Allocator, Global, Layout, AllocError}
import alloc.string.ToString
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import core.default.Default
import core.fmt
import core.hash.{Hash, Hasher}
import core.text.Text

type OtherAllocator {}
unsafe extend OtherAllocator implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        var global = Global()
        try global.allocate(layout)
    }
    mut unsafe fn deallocate(pointer: ptr<mut u8>, layout: Layout): Unit {
        var global = Global()
        unsafe { global.deallocate(pointer, layout) }
    }
    mut unsafe fn grow(pointer: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError {
        var global = Global()
        unsafe { try global.grow(pointer, old, size) }
    }
    mut unsafe fn shrink(pointer: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError {
        var global = Global()
        unsafe { try global.shrink(pointer, old, size) }
    }
}

type Different { value: i32 }
extend i32 implements PartialEq<Different> {
    fn eq(read other: Different): bool { self == other.value }
}
extend i32 implements PartialOrd<Different> {
    fn partial_cmp(read other: Different): Ordering? { self.partial_cmp(read other.value) }
}
extend Different implements PartialEq<i32> {
    fn eq(read other: i32): bool { self.value == other }
}
extend Different implements PartialOrd<i32> {
    fn partial_cmp(read other: i32): Ordering? { self.value.partial_cmp(other) }
}

fn compares<L: PartialEq<R> + PartialOrd<R>, R>(read left: L, read right: R, expected: Ordering): Unit {
    assert(left.eq(right) == expected.is_eq() && left.partial_cmp(right) == present(expected),
        "pinned comparison delegates to the cross-target relation")
}

fn ordered<T: Eq + Ord>(read left: T, read right: T): Unit {
    assert(left.cmp(right) == Ordering.Less && !left.eq(right), "pinned total ordering follows payload order")
}

fn hashed<T: Hash>(read value: T): u64 {
    var state = core.hash.fnv1a()
    value.hash(mut state)
    state.finish()
}

fn formatted<T: fmt.Debug + fmt.Display>(read value: T, read expected: Text, read debug: Text): Unit {
    assert(value.to_string().as_text() == expected, "pinned Display delegates to the pointer payload")
    var output = alloc.string.new()
    {
        var formatter = fmt.formatter(mut output, fmt.spec())
        match capture T.(fmt.Debug).fmt(value, mut formatter) {
            success(_) => {},
            failure(_) => { core.panic.panic("debug formatting failed") }
        }
    }
    assert(output.as_text() == debug, "pinned Debug delegates to the pointer payload")
    var bytes: [u8; 0] = []
    var writer = fmt.buffer_writer(mut bytes)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    if expected.as_bytes().len() != 0usize {
        assert((capture T.(fmt.Display).fmt(value, mut formatter)).is_failure(), "pinned Display propagates writer failure")
    }
    assert((capture T.(fmt.Debug).fmt(value, mut formatter)).is_failure(), "pinned Debug propagates writer failure")
}

fn main(): i32 {
    let b = boxed.pin(11)
    let r = rc.pin(11)
    let a = arc.pin(11)
    let bd = boxed.pin(Different(11))
    let rd = rc.pin(Different(11))
    let ad = arc.pin(Different(11))
    compares(b, bd, Ordering.Equal)
    compares(b, rd, Ordering.Equal)
    compares(b, ad, Ordering.Equal)
    compares(r, bd, Ordering.Equal)
    compares(r, rd, Ordering.Equal)
    compares(r, ad, Ordering.Equal)
    compares(a, bd, Ordering.Equal)
    compares(a, rd, Ordering.Equal)
    compares(a, ad, Ordering.Equal)
    compares(bd, b, Ordering.Equal)
    compares(rd, r, Ordering.Equal)
    compares(ad, a, Ordering.Equal)
    let alternate = boxed.new_in(Different(12), OtherAllocator()).into_pinned()
    compares(b, alternate, Ordering.Less)
    compares(r, alternate, Ordering.Less)
    compares(a, alternate, Ordering.Less)
    compares(alternate, b, Ordering.Greater)
    compares(alternate, r, Ordering.Greater)
    compares(alternate, a, Ordering.Greater)
    ordered(b, boxed.pin(12))
    ordered(r, rc.pin(12))
    ordered(a, arc.pin(12))
    assert(hashed(b) == hashed(11) && hashed(r) == hashed(11) && hashed(a) == hashed(11),
        "pinned hash ignores allocation and owner kind")
    formatted(b, "11", "11")
    formatted(r, "11", "11")
    formatted(a, "11", "11")

    let borrowed = bd.as_ref()
    compares(b, borrowed, Ordering.Equal)
    compares(r, borrowed, Ordering.Equal)
    compares(a, borrowed, Ordering.Equal)
    compares(borrowed, b, Ordering.Equal)
    compares(borrowed, r, Ordering.Equal)
    compares(borrowed, a, Ordering.Equal)
    var exclusive_owner = boxed.pin(Different(11))
    {
        let exclusive = exclusive_owner.as_mut()
        compares(b, exclusive, Ordering.Equal)
        compares(r, exclusive, Ordering.Equal)
        compares(a, exclusive, Ordering.Equal)
        compares(exclusive, b, Ordering.Equal)
        compares(exclusive, r, Ordering.Equal)
        compares(exclusive, a, Ordering.Equal)
    }
    let empty_box = boxed.copy_text("").into_pinned()
    let empty_rc = rc.Pinned<Text>.default()
    let empty_arc = arc.Pinned<Text>.default()
    compares(empty_box, empty_rc, Ordering.Equal)
    compares(empty_rc, empty_arc, Ordering.Equal)
    compares(empty_arc, empty_box, Ordering.Equal)
    assert(hashed(empty_box) == hashed(empty_rc) && hashed(empty_rc) == hashed(empty_arc),
        "unsized text metadata survives pinned hash delegation")
    formatted(empty_box, "", "\"\"")
    formatted(empty_rc, "", "\"\"")
    formatted(empty_arc, "", "\"\"")
    0
}
