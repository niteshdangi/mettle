import alloc.collections.List

type Store<V> { entries: List<V> }
type Slot<region r, V> { store: mut Store<V> from r; index: usize }

extend<region r, V> Slot<region r, V> {
    pub mut fn get_mut(): mut V from self {
        unsafe { mut *self.store.entries.as_mut_ptr().add(self.index) }
    }
}

fn modify_slot<region r, V, F: take fn(mut V): Unit>(slot: take Slot<region r, V>, modify: take F): Slot<region r, V> {
    var held = slot
    modify(held.get_mut())
    held
}

fn main(): i32 {
    var store = Store(List<i32>())
    store.entries.push(41)
    {
        let _ = modify_slot(Slot(mut store, 0), take fn(value: mut i32): Unit { value += 1 })
    }
    if *store.entries.get(0).unwrap() != 42 { return 1 }
    0
}
