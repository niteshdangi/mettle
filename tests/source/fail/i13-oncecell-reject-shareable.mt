// expect-error: type 5:5 unsatisfied interface bound 'Shareable'
import core.cell.OnceCell
fn shareable<T: Shareable>() {}
fn main() {
    shareable<OnceCell<i32>>()
}
