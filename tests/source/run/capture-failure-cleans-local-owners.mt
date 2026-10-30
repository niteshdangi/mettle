
type Guard<region r> { log: mut i32 from r; drop { *self.log += 1 } }
fn fail(): i32 throws i32 { throw 7 }
fn main() {
    var log = 40
    let result = capture { let guard = Guard(mut log); fail() + 1 }
    { let guard = Guard(mut log) }
    match result { success(_) => 1, failure(error) => if error == 7 && log == 42 { 0 } else { 1 } }
}
