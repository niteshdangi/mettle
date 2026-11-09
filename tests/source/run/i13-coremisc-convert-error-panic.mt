// profiles: debug release
// Evidence for the AsRef and AsMut conversions, the Error source chain, and
// the panic payload produced by library panics.

import core.borrow.{AsMut, AsRef}
import core.error.Error
import core.fmt.{Debug, Display, Error as FmtError, Formatter}
import std.panic.{ catch_panic, CatchResult }

type Wrapper { value: i32 }
extend Wrapper implements AsRef<i32> {
    fn as_ref(): read i32 from self { read self.value }
}
extend Wrapper implements AsMut<i32> {
    mut fn as_mut(): mut i32 from self { mut self.value }
}

type Leaf {}
extend Leaf implements Debug {
    fn fmt(mut f: Formatter): Unit throws FmtError { try f.write_str("leaf") }
}
extend Leaf implements Display {
    fn fmt(mut f: Formatter): Unit throws FmtError { try f.write_str("leaf") }
}
extend Leaf implements Error {}

type Branch { cause: Leaf }
extend Branch implements Debug {
    fn fmt(mut f: Formatter): Unit throws FmtError { try f.write_str("branch") }
}
extend Branch implements Display {
    fn fmt(mut f: Formatter): Unit throws FmtError { try f.write_str("branch") }
}
extend Branch implements Error {
    fn source<region r>(receiver read self: Branch from r): (read any Error from r)? {
        let cause: read any Error = read self.cause
        present(cause)
    }
}

fn read_through<T: AsRef<i32>>(read value: T): i32 { *value.as_ref() }
fn write_through<T: AsMut<i32>>(mut target: T, value: i32): Unit { *target.as_mut() = value }

fn checks_convert(): i32 {
    var wrapper = Wrapper(5)
    if read_through(read wrapper) != 5 { return 1 }
    write_through(mut wrapper, 9)
    if read_through(read wrapper) != 9 { return 2 }
    0
}

fn checks_error(): i32 {
    if Leaf().source().is_present() { return 10 }
    if Branch(Leaf()).source().is_none() { return 11 }
    0
}

fn checks_panic(): i32 {
    let outcome = catch_panic(fn(): Unit {
        let absent: i32? = none
        let _ = absent.unwrap()
    })
    match outcome {
        CatchResult.Panicked(info) => { if info.code() != 101 { return 20 } },
        CatchResult.Returned(_) => { return 21 }
    }
    0
}

fn main(): i32 {
    let convert_status = checks_convert()
    if convert_status != 0 { return convert_status }
    let error_status = checks_error()
    if error_status != 0 { return error_status }
    checks_panic()
}
