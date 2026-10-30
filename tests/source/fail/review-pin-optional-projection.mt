// expect-error: feature 6:17 pin projection of sum variants

fn main() {
    var value:i32? = none
    var handle = core.pin.Pin.new(mut value)
    let inner = handle.project_value()
    0
}
