// expect-error: name 4:9 duplicate associated item
module model { pub type Widget {} }
extend model.Widget {
    pub const value: i32 = 1
}
import model.Widget
extend Widget {
    pub static fn value(): i32 { 0 }
}
fn main(): i32 { 0 }
