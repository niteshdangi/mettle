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
type Other { value: i32 }
extend Other implements PartialEq<Different> {
    fn eq(read other: Different): bool { self.value == other.value }
}
extend Other implements PartialOrd<Different> {
    fn partial_cmp(read other: Different): Ordering? { self.value.partial_cmp(read other.value) }
}
extend Different implements PartialEq<Other> {
    fn eq(read other: Other): bool { self.value == other.value }
}
extend Different implements PartialOrd<Other> {
    fn partial_cmp(read other: Other): Ordering? { self.value.partial_cmp(read other.value) }
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
    let bo = boxed.pin(Other(11))
    let ro = rc.pin(Other(11))
    let ao = arc.pin(Other(11))
    let bd = boxed.pin(Different(11))
    let rd = rc.pin(Different(11))
    let ad = arc.pin(Different(11))
    compares(bo, bd, Ordering.Equal)
    compares(bo, rd, Ordering.Equal)
    compares(bo, ad, Ordering.Equal)
    compares(ro, bd, Ordering.Equal)
    compares(ro, rd, Ordering.Equal)
    compares(ro, ad, Ordering.Equal)
    compares(ao, bd, Ordering.Equal)
    compares(ao, rd, Ordering.Equal)
    compares(ao, ad, Ordering.Equal)
    compares(bd, bo, Ordering.Equal)
    compares(rd, ro, Ordering.Equal)
    compares(ad, ao, Ordering.Equal)
    let alternate = boxed.new_in(Different(12), OtherAllocator()).into_pinned()
    compares(bo, alternate, Ordering.Less)
    compares(ro, alternate, Ordering.Less)
    compares(ao, alternate, Ordering.Less)
    compares(alternate, bo, Ordering.Greater)
    compares(alternate, ro, Ordering.Greater)
    compares(alternate, ao, Ordering.Greater)
    ordered(b, boxed.pin(12))
    ordered(r, rc.pin(12))
    ordered(a, arc.pin(12))
    assert(hashed(b) == hashed(11) && hashed(r) == hashed(11) && hashed(a) == hashed(11),
        "pinned hash ignores allocation and owner kind")
    formatted(b, "11", "11")
    formatted(r, "11", "11")
    formatted(a, "11", "11")

    let borrowed = bd.as_ref()
    compares(bo, borrowed, Ordering.Equal)
    compares(ro, borrowed, Ordering.Equal)
    compares(ao, borrowed, Ordering.Equal)
    compares(borrowed, bo, Ordering.Equal)
    compares(borrowed, ro, Ordering.Equal)
    compares(borrowed, ao, Ordering.Equal)
    var exclusive_owner = boxed.pin(Different(11))
    {
        let exclusive = exclusive_owner.as_mut()
        compares(bo, exclusive, Ordering.Equal)
        compares(ro, exclusive, Ordering.Equal)
        compares(ao, exclusive, Ordering.Equal)
        compares(exclusive, bo, Ordering.Equal)
        compares(exclusive, ro, Ordering.Equal)
        compares(exclusive, ao, Ordering.Equal)
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
