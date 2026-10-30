
type Guard<region r> { log: mut i32 from r; drop { *self.log += 1 } }
copy type Logs { first: i32; second: i32 }
fn main() {
    var logs = Logs(20, 20)
    { let array = [Guard(mut logs.first), Guard(mut logs.second)]; for guard in take array {} }
    if logs.first + logs.second == 42 { 0 } else { 1 }
}
