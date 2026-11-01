import alloc.arc
import alloc.boxed
import alloc.rc
import core.default.Default

type Seed { value: i32 }

extend Seed implements Default {
    static fn default(): Seed { Seed(73) }
}

fn default_value<T: Default>(): T { T.(Default).default() }

fn main(): i32 {
    let boxed_value = default_value<boxed.Box<Seed>>()
    let local_value = default_value<rc.Rc<Seed>>()
    let atomic_value = default_value<arc.Arc<Seed>>()
    if boxed_value.get().value != 73 ||
        local_value.get().value != 73 ||
        atomic_value.get().value != 73 {
        return 1
    }

    let boxed_slice = default_value<boxed.Box<[Seed]>>()
    let local_slice = default_value<rc.Rc<[Seed]>>()
    let atomic_slice = default_value<arc.Arc<[Seed]>>()
    if boxed_slice.get().len() != 0usize ||
        local_slice.get().len() != 0usize ||
        atomic_slice.get().len() != 0usize {
        return 2
    }

    let boxed_text = default_value<boxed.Box<core.text.Text>>()
    let local_text = default_value<rc.Rc<core.text.Text>>()
    let atomic_text = default_value<arc.Arc<core.text.Text>>()
    if boxed_text.get().len() != 0usize ||
        local_text.get().len() != 0usize ||
        atomic_text.get().len() != 0usize {
        return 3
    }

    let boxed_pinned = default_value<boxed.Pinned<Seed>>()
    let local_pinned = default_value<rc.Pinned<Seed>>()
    let atomic_pinned = default_value<arc.Pinned<Seed>>()
    if boxed_pinned.get_ref().value != 73 ||
        local_pinned.get_ref().value != 73 ||
        atomic_pinned.get_ref().value != 73 {
        return 4
    }

    let boxed_pinned_slice = default_value<boxed.Pinned<[Seed]>>()
    let local_pinned_slice = default_value<rc.Pinned<[Seed]>>()
    let atomic_pinned_slice = default_value<arc.Pinned<[Seed]>>()
    if boxed_pinned_slice.get_ref().len() != 0usize ||
        local_pinned_slice.get_ref().len() != 0usize ||
        atomic_pinned_slice.get_ref().len() != 0usize {
        return 5
    }

    let boxed_pinned_text = default_value<boxed.Pinned<core.text.Text>>()
    let local_pinned_text = default_value<rc.Pinned<core.text.Text>>()
    let atomic_pinned_text = default_value<arc.Pinned<core.text.Text>>()
    if boxed_pinned_text.get_ref().len() != 0usize ||
        local_pinned_text.get_ref().len() != 0usize ||
        atomic_pinned_text.get_ref().len() != 0usize {
        return 6
    }
    0
}
