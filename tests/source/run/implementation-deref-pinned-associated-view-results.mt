import core.ops.{Deref, DerefMut}

type PinnedField<T> { @pinned value: T }

extend<T> PinnedField<T> implements Deref {
    type Target = T
    fn deref(): read T from self { read self.value }
}

extend<T> PinnedField<T> implements DerefMut {
    mut fn deref_mut(): mut T from self { mut self.value }
}

fn main(): i32 {
    var value = PinnedField(7)
    if *value.deref() != 7 { return 1 }
    *value.deref_mut() = 9
    if *value.deref() != 9 { return 2 }
    0
}
