import alloc.arc.Arc
import alloc.rc.Rc
import alloc.string.String
import package.core.text.Text

fn main(): i32 {
    var source = String("valid UTF-8")
    let atomic = Arc<Text>.copy_text(source.as_text())
    let local = Rc<Text>.copy_text("also valid")
    source.clear()
    if atomic.get() != "valid UTF-8" || local.get() != "also valid" {
        return 1
    }
    0
}
