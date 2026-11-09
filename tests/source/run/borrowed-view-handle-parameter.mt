
fn observe(value: (mut i32)) { *value }
fn observe_read(read value: (read i32)) { *value }
fn main() {
    var value = 42
    {
        let exclusive = mut value
        if observe(exclusive) != 42 { return 1 }
    }
    let view = read value
    if observe_read(view) == 42 { 0 } else { 1 }
}
