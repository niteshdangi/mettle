import alloc.rc

fn main(): i32 {
    let observer = {
        let strong = rc.new(41)
        let strong_pointer = strong.as_ptr()
        let observer = strong.downgrade()
        if strong_pointer != observer.as_ptr() { return 1 }
        observer
    }

    if observer.strong_count() != 0usize { return 2 }
    if observer.upgrade().is_present() { return 3 }
    0
}
