import std.io.Cursor

const fn positioned(): Cursor<i32> {
    var cursor = Cursor.new(7i32)
    cursor.set_position(11u64)
    *cursor.get_mut() = 9i32
    cursor
}

const CURSOR: Cursor<i32> = positioned()
const POSITION: u64 = CURSOR.position()
const INNER: i32 = *CURSOR.get_ref()

fn main(): i32 {
    assert(POSITION == 11u64 && INNER == 9i32, "required evaluation preserves cursor state")
    var cursor = positioned()
    assert(cursor.position() == 11u64 && cursor.into_inner() == 9i32, "runtime agrees with const")
    0
}
