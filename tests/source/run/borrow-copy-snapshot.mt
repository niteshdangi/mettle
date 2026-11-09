
fn change(mut value: i32) { value = 100; 1 }
fn combine(first: i32, second: i32) { first + second }
fn main() {
    var value = 41
    let result = combine(value, change(value))
    if result == 42 && value == 100 { 0 } else { 1 }
}
