
module core {
    pub module ops {
        pub interface Deref { type Target; fn deref(): read Self.Target; }
        pub interface DerefMut: Deref { mut fn deref_mut(): mut Self.Target; }
    }
}
type Inner {
    value: i32
    fn get(): i32 { self.value }
    mut fn increment(): Unit { self.value += 1 }
}
type Wrapper { inner: Inner; projections: i32 }
extend Wrapper implements core.ops.Deref {
    type Target = Inner
    fn deref(): read Inner { read self.inner }
}
extend Wrapper implements core.ops.DerefMut {
    mut fn deref_mut(): mut Inner {
        self.projections += 1
        mut self.inner
    }
}
fn increment(mut value: Inner) { value.increment() }
fn main() {
    var wrapper = Wrapper(Inner(39),0)
    wrapper.increment()
    increment(wrapper)
    let operation: fn(mut Inner): Unit = increment
    operation(wrapper)
    if wrapper.get() == 42 && wrapper.projections == 3 { 0 } else { 1 }
}
