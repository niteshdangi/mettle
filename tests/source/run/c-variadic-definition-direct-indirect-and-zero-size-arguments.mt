
@layout(C)
copy type Empty {}
unsafe extern "C" fn inspect(count: i32,args: ...): i32 {
    let empty = args.arg<Empty>()
    args.arg<i32>()
}
fn main() {
    let callback: unsafe extern "C" fn(i32,...): i32 = inspect
    let first = unsafe { inspect(1,Empty(),42) }
    let second = unsafe { callback(1,Empty(),42) }
    if first == 42 && second == 42 { 0 } else { 1 }
}
