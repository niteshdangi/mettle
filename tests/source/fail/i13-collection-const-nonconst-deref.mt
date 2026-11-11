// profiles: debug release
// expect-error: constant 19:5 call to non-const function 'deref' in a constant expression
// expect-error-count: 1
import core.ops.Deref

type Inner {
    value: i32
}
extend Inner {
    const fn get(): i32 { self.value }
}
type Wrapper { inner: Inner }
extend Wrapper implements Deref {
    type Target = Inner
    fn deref(): read Inner from self { read self.inner }
}
const fn projected(): i32 {
    let wrapper = Wrapper(Inner(1))
    wrapper.get()
}
static VALUE: i32 = projected()
