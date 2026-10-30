// expect-error: type 8:5 not dispatchable

interface Generic { fn accept<T>(value: T): Unit; }
type Number {}
extend Number implements Generic { fn accept<T>(value: T): Unit {} }
fn main() {
    let value = Number()
    let erased: read any Generic = read value
    0
}
