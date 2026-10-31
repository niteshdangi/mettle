import alloc.arc
import alloc.rc

fn main(): i32 {
    var uninit = rc.Rc<i32>.new_uninit_slice(2usize)
    {
        let slots = match uninit.get_mut() {
            present(view) => view,
            none => { return 1 }
        }
        let _first = slots[0usize].write(4)
    }
    {
        let slots = match uninit.get_mut() {
            present(view) => view,
            none => { return 2 }
        }
        let _second = slots[1usize].write(5)
    }
    let ready = unsafe { uninit.assume_init() }
    if ready.get()[0usize] != 4 || ready.get()[1usize] != 5 { return 3 }

    let zeros = rc.new_zeroed_slice<i32>(3usize)
    let values = unsafe { zeros.get().assume_init_ref() }
    if values.len() != 3usize || values[0usize] != 0 || values[2usize] != 0 { return 4 }

    let empty = rc.new_uninit_slice<i32>(0usize)
    if empty.get().len() != 0usize { return 5 }

    var shared = arc.Arc<i32>.new_zeroed_slice(1usize)
    {
        let slots = match shared.get_mut() {
            present(view) => view,
            none => { return 6 }
        }
        let _written = slots[0usize].write(8)
    }
    let initialized = unsafe { shared.assume_init() }
    if initialized.get()[0usize] != 8 { return 7 }
    0
}
