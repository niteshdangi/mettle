// expect-error: ownership 17:5 requires matching DerefMut

module core {
    pub module ops {
        pub interface Deref { type Target; fn deref(): read Self::Target; }
    }
}
import core::ops::Deref
type Inner { mut fn increment(): Unit {} }
type Wrapper { inner: Inner }
impl Wrapper implements core::ops::Deref {
    type Target = Inner
    fn deref(): read Inner { read self.inner }
}
fn main() {
    var wrapper = Wrapper(Inner())
    wrapper.increment()
    0
}
