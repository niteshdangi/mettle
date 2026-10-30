// expect-error: signature 2:67 conflicting external
@export_name("same") static FIRST: i32 = 42; @export_name("same") static SECOND: i32 = 42; fn main() { 0 }
