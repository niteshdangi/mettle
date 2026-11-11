// profiles: debug release
import core.ops.{Deref, DerefMut}

type Wrapper { value: i32 }
extend Wrapper implements Deref {
    type Target = i32
    fn deref(): read i32 from self { read self.value }
}
extend Wrapper implements DerefMut {
    mut fn deref_mut(): mut i32 from self { mut self.value }
}

fn inspect<T: DerefMut>(read value: T): Unit {
    let _ = value.deref()
}
fn set<T: DerefMut>(mut value: T, take replacement: T.(Deref).Target): Unit where T.(Deref).Target: Sized {
    *value.deref_mut() = replacement
}

fn main(): i32 {
    var value = Wrapper(1)
    inspect(read value)
    set(mut value, 9)
    if *value.deref() == 9 { 0 } else { 1 }
}
