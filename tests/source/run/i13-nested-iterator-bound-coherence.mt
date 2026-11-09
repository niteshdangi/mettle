// profiles: debug release
interface NextLike {}
interface IntoLike {}
type Wrapper<T> { value: T }
type Container<T> { value: T }
extend<T: NextLike> Wrapper<T> implements NextLike {}
extend<T: NextLike> T implements IntoLike {}
extend<T> Wrapper<Container<T>> implements IntoLike {}
extend i32 implements NextLike {}
fn accept<T: IntoLike>(take value: T) {}
fn main(): i32 {
    accept(Wrapper(Container(1)))
    accept(Wrapper(2))
    0
}
