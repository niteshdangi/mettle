// expect-exit: 0
// profiles: debug release
// Blanket and auto-property evidence for Cursor, Lines, ReadDir, Peekable, ManuallyDrop, Pinned and arrays.
fn any_ok<T: unsized + core.any.Any>(): Unit {}
fn borrow_ok<T: unsized + core.borrow.Borrow<T>>(): Unit {}
fn owned_ok<T: core.borrow.ToOwned>(): Unit {}
fn from_ok<T: core.convert.From<T>>(): Unit {}
fn into_ok<T: core.convert.Into<T>>(): Unit {}
fn string_ok<T: alloc.string.ToString>(): Unit {}
fn send_ok<T: unsized + Transferable>(): Unit {}
fn sync_ok<T: unsized + Shareable>(): Unit {}
alias A_cursor = std.io.Cursor<[u8; 4]>
alias A_peekable = core.iter.Peekable<core.iter.Range<i32>>
alias A_pinned = alloc.boxed.Pinned<i32>
alias A_lines = std.io.Lines<std.io.BufferedReader<std.io.Stdin>>
alias A_drop = core.mem.ManuallyDrop<i32>
fn owned_slice_iterators<region r>(read items: [i32] from r): Unit {
    owned_ok<core.slice.SliceChunks<region r, i32>>()
    owned_ok<core.slice.SliceWindows<region r, i32>>()
}
fn main(): i32 {
    owned_slice_iterators([1, 2, 3])
    borrow_ok<A_cursor>()
    owned_ok<A_cursor>()
    from_ok<A_cursor>()
    into_ok<A_cursor>()
    send_ok<A_cursor>()
    sync_ok<A_cursor>()
    send_ok<std.fs.ReadDir>()
    sync_ok<std.fs.ReadDir>()
    borrow_ok<A_lines>()
    from_ok<A_lines>()
    into_ok<A_lines>()
    send_ok<A_lines>()
    sync_ok<A_lines>()
    owned_ok<A_peekable>()
    owned_ok<A_drop>()
    owned_ok<core.future.Poll<i32>>()
    owned_ok<core.future.Waker>()
    any_ok<A_pinned>()
    borrow_ok<A_pinned>()
    owned_ok<A_pinned>()
    from_ok<A_pinned>()
    into_ok<A_pinned>()
    string_ok<A_pinned>()
    send_ok<A_pinned>()
    sync_ok<A_pinned>()
    owned_ok<[i32; 3]>()
    0
}
