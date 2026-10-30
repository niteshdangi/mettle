
copy type Empty {}
copy type Flag {
    tag: Empty
    completed: Unit
    enabled: bool
}
fn swap(flag: Flag) { Flag(flag.tag, flag.completed, !flag.enabled) }
fn Unit(value: i32) { value }
fn main() {
    let placeholder: Flag
    let _ = placeholder.enabled
    var flag = Flag(Empty(), (), true)
    let snapshot = flag
    flag = swap(flag)
    if snapshot.enabled && !flag.enabled && flag.completed == () && Unit(42) == 42 { 0 } else { 1 }
}
