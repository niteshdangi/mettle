
alias SharedInt = read i32
alias ExclusiveInt = mut i32
fn identity(read value: i32): SharedInt from value { read value }
fn inspect(read value: (ExclusiveInt)) { *value }
fn main() {
    var value = 40
    { let exclusive: ExclusiveInt = mut value; *exclusive += 2; let observed = inspect(exclusive) }
    let view: SharedInt = identity(value)
    if *view == 42 { 0 } else { 1 }
}
