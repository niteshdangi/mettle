// expect-error: type 6:31 incompatible aggregate shape
import alloc.arc
import core.text.Text

fn main(): i32 {
    let owner = arc.copy_text([0xffu8, 0xffu8])
    owner.get().len() as i32
}
