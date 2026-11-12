// expect-error: type 9:5 unsatisfied interface bound 'Transferable'
// expect-error: type 10:5 unsatisfied interface bound 'Shareable'
// expect-error: type 11:5 unsatisfied interface bound 'Transferable'
// expect-error: type 12:5 unsatisfied interface bound 'Shareable'
import core.fmt.{Formatter, Message}
fn transferable<T: Transferable>() {}
fn shareable<T: Shareable>() {}
fn main() {
    transferable<Message<region static>>()
    shareable<Message<region static>>()
    transferable<Formatter<region static>>()
    shareable<Formatter<region static>>()
}
