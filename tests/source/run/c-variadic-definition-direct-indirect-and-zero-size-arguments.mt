import core.ffi.VaList
import core.clone.Clone
@layout(C)
copy type Empty {}
unsafe extern "C" fn inspect(count: i32,args: ...): i32 {
    let empty = args.arg<Empty>()
    args.arg<i32>()
}
fn borrowed<region frame>(mut cursor: VaList<region frame>): i32 {
    unsafe { cursor.next_arg<i32>() }
}
unsafe extern "C" fn independent(count: i32, args: ...): i32 {
    let first = borrowed(mut args)
    var duplicate = args.clone()
    let wide = args.next_arg<i128>()
    let duplicated_wide = duplicate.next_arg<i128>()
    let floating = args.next_arg<f64>()
    let duplicated_floating = duplicate.next_arg<f64>()
    if wide != duplicated_wide || floating != duplicated_floating { return -1 }
    first + (wide as i32) + (floating as i32)
}
fn main() {
    let callback: unsafe extern "C" fn(i32,...): i32 = inspect
    let first = unsafe { inspect(1,Empty(),42) }
    let second = unsafe { callback(1,Empty(),42) }
    let copied = unsafe { independent(3, 10i32, 12i128, 20f64) }
    if first == 42 && second == 42 && copied == 42 { 0 } else { 1 }
}
