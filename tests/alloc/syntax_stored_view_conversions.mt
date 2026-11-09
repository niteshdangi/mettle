import alloc.rc.Rc
import alloc.arc.Arc
import core.text.Text
import core.convert.From

fn main(): i32 {
    var values = alloc.vec.new<i32>()
    values.push(4)
    values.push(5)
    let rc_values = Rc<[i32]>.(From<read [i32]>).from(values.as_slice())
    let arc_values = Arc<[i32]>.(From<read [i32]>).from(values.as_slice())
    values[0] = 9
    if rc_values.get()[0] != 4 || arc_values.get()[0] != 4 { return 1 }

    var text = alloc.string.new()
    text.push_str("hello")
    let local_text = Rc<Text>.(From<read Text>).from(text.as_text())
    let shared_text = Arc<Text>.(From<read Text>).from(text.as_text())
    text.clear()
    text.push_str("world!")
    if local_text.get().len() != 5usize || shared_text.get().len() != 5usize { return 2 }
    if local_text.get().as_bytes()[0] != b'h' ||
        shared_text.get().as_bytes()[0] != b'h' { return 3 }
    0
}
