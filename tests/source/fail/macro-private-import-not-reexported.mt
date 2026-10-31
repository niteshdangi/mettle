// expect-error: name 9:18 private macro 'value' is not visible from this module
module original {
    pub macro value { () => { 42 }; }
}
module api {
    import original.value
}
import api.value
fn main(): i32 { value!() }
