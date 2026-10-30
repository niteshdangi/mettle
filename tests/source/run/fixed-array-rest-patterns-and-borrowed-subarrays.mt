
type Owned { value: i32 }
fn total(values: read [Owned; 2]) { values[0].value + values[1].value }
fn main() {
    let array = [Owned(1), Owned(20), Owned(22), Owned(2)]
    let answer = match array { [_, middle @ .., _] => total(middle) }
    let [first, rest @ ..] = [20, 10, 12]
    if answer == 42 && first + rest[0] + rest[1] == 42 { 0 } else { 1 }
}
