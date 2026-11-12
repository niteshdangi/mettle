// expect-error: type 5:5 unsatisfied interface bound 'Transferable'
import core.cell.OnceCell
fn transferable<T: Transferable>() {}
fn main() {
    transferable<OnceCell<ptr<mut i32>>>()
}
