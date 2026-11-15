interface Iter {}
interface Owned {}

type Boxed<T> { value: T }
type Vector<T> { value: T }

extend<I: Iter> Boxed<I> implements Iter {}
extend<T: Iter> T implements Owned {}
extend<T> Vector<T> implements Owned {}

fn main(): i32 { 0 }
