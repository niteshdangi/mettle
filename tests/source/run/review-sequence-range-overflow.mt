// profiles: debug release
// expect-exit-debug: trap
// expect-exit-release: 0
import core.iter.{Iterator, range_from}
fn main(): i32 {
    var source = range_from(u8.MAX)
    assert(source.next() == present(u8.MAX), "release yields endpoint")
    assert(source.next() == present(0u8), "release wraps rather than silently ending")
    0
}
