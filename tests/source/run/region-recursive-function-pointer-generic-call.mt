// A type that recurses through a function-pointer field compares equal to
// itself when passed as a view to a generic callee.
copy type V { clone: fn(ptr<mut u8>): R }
copy type R { data: ptr<mut u8>; v: V }
fn same(data: ptr<mut u8>): R { R(data, V(same)) }
fn gr<T>(w: read R): bool { w.data == core::ptr::null_mut::<u8>() }
fn er(slot: ptr<mut u8>): bool { unsafe { gr::<i32>(read *slot.cast::<R>()) } }
fn main(): i32 {
    var r = same(core::ptr::null_mut::<u8>())
    if er(core::ptr::from_mut(r).cast::<u8>()) { 0 } else { 1 }
}
