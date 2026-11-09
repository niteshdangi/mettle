// expect-error: type 8:5 not dispatchable

interface Equal { fn equal(other: Self): bool; }
type Number {}
extend Number implements Equal { fn equal(read other: Number): bool { true } }
fn main() {
    let value = Number()
    let erased: read any Equal = read value
    0
}
