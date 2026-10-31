import alloc.arc
import alloc.rc
import alloc.string.String
import package.core.text.Text

fn main(): i32 {
    var source = String("valid UTF-8")
    let atomic = arc.copy_text(source.as_text())
    let counted = rc.copy_text("also valid")
    source.clear()
    if atomic.get() != "valid UTF-8" || counted.get() != "also valid" {
        return 1
    }
    0
}
