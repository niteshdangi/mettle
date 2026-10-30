
fn main() {
    var handle = core.pin.pin(40i32)
    let view = handle.as_mut().get_mut()
    *view += 2
    let reference = handle.as_ref().get_ref()
    if *reference == 42 { 0 } else { 1 }
}
