// expect-error: type 6:37 expected Text
import alloc.arc.Arc
import package.core.text.Text

fn main(): i32 {
    let owner = Arc<Text>.copy_text([0xffu8, 0xffu8])
    owner.get().len() as i32
}
