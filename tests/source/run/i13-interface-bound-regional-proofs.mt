// profiles: debug release
import core.text.Text
interface StaticRange {}
type RefRange<T> { value: T }
extend<region r> RefRange<read Text from r> implements StaticRange where region r: static {}
fn require<R: StaticRange>(read value: R) {}
fn validate_static<region r>(take input: read Text from r): Unit where region r: static {
    let range = RefRange(input)
    require(read range)
}

interface SameRegion {}
extend<region r> (core.cell.Cell<read i32 from r>, core.cell.Cell<read i32 from r>) implements SameRegion {}
fn require_same<R: SameRegion>(read value: R) {}
fn validate_same<region r>(take first: core.cell.Cell<read i32 from r>, take second: core.cell.Cell<read i32 from r>) {
    require_same(read (take first, take second))
}

static VALUES: [i32; 2] = [1, 2]
fn main(): i32 {
    validate_static("static view")
    var first = core.cell.Cell.new(read VALUES[0usize])
    var second = core.cell.Cell.new(read VALUES[1usize])
    validate_same(take first, take second)
    0
}
