
type Box<T: Copy> {
    value: T
    init(value: T) { self.value = value }
    fn get(): T { self.value }
}
alias PairBox<T: Copy> = Box<(T,i32)>
enum Choice<T: Copy> { Empty; Value(T) }
fn main(): i32 {
    let boxed = Box(42)
    let pair = PairBox::<i32>((42,0))
    let result = Choice::Value(boxed.get())
    let answer = match result {
        Choice::Empty => 0,
        Choice::Value(value) => value
    }
    if answer == 42 && pair.get().0 == 42 { 0 } else { 1 }
}
