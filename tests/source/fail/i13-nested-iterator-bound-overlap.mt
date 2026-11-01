// expect-error: type 9:1 overlapping implementations cannot be selected by order
interface NextLike {}
interface IntoLike {}
type Wrapper<T> { value: T }
type Container<T> { value: T }
extend<T: NextLike> Wrapper<T> implements NextLike {}
extend<T> Container<T> implements NextLike {}
extend<T: NextLike> T implements IntoLike {}
extend<T> Wrapper<Container<T>> implements IntoLike {}
fn main(): i32 { 0 }
