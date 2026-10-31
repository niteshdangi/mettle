// expect-error: name 5:13 unresolved or inaccessible function 'get_mut'
async fn seven(): i32 { 7 }
fn main(): i32 {
    var p = pinned heap seven()
    let m = p.get_mut()
    0
}
