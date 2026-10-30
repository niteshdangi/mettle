
alias Stop = Never
type Arithmetic {
    static fn twice(value: i32) { Self::add(value, value) }
    static fn add(first: i32, second: i32) { first + second }
    static fn forever(): Stop { loop {} }
    static fn inferred_forever() { Self::forever() }
}
fn main() { if Arithmetic::twice(21) == 42 { 0 } else { 1 } }
