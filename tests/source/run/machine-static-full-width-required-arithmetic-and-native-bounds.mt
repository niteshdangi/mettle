
static FIRST: u128 = 1267650600228229401496703205376u128;
static SECOND: u128 = FIRST + 42u128;
static MAXIMUM: u128 = u128.MAX - 1u128;
static NEGATIVE: i128 = i128.MIN + 42i128;
fn mask<const B: bool = true | false>(): bool { B }
fn main() {
    if SECOND - FIRST == 42u128 && MAXIMUM + 1u128 == u128.MAX &&
       NEGATIVE - i128.MIN == 42i128 && mask() { 0 } else { 1 }
}
