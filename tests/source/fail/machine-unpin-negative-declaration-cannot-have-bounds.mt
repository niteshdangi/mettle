// expect-error: type 4:1 negative Unpin declarations cannot specialize bounds

type Wrapper<T> { value: T }
impl<T: Copy> Wrapper<T> not Unpin;
fn main() { 0 }
