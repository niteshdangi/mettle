module model { pub type Widget {} }
import model.Widget
extend Widget {
    pub static fn answer(): i32 { 42 }
    pub const VALUE: i32 = 42
}
import Widget.{answer, VALUE}
alias WidgetAlias = Widget
fn main(): i32 { answer() + VALUE + WidgetAlias.answer() - 126 }
