
interface Readable { fn value(): i32; }
extend i32 implements Readable { fn value(): i32 { self } }
type Tail<T: unsized> { header: bool; value: T }
fn inspect(value: read Tail<any Readable>): i32 {
    if value.header { value.value.value() } else { 1 }
}
fn main() {
    let value = Tail(true,42)
    let erased: read Tail<any Readable> = read value
    if inspect(erased) == 42 { 0 } else { 1 }
}
