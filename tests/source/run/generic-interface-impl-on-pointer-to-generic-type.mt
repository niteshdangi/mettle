
import core.cmp.PartialEq
type Cell2<T> { v: T }
type R<T> { p: ptr<mut Cell2<T>> }
extend<T> R<T> { fn get(): read T from self { unsafe { read (*self.p).v } } }
extend<T: PartialEq> R<T> implements PartialEq { fn eq(read other: R<T>): bool { self.get().eq(other.get()) } }
type Node<T> { v: T; next: ptr<mut Node<T>> }
type L<T> { head: ptr<mut Node<T>> }
extend<T> L<T> { fn first(): (read T from self)? { if self.head == core.ptr.null_mut<Node<T>>() { none } else { present(unsafe { read (*self.head).v }) } } }
fn main(): i32 { 0 }
