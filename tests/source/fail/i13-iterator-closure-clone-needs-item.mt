// expect-error: type 16:5 no implementation of 'any Clone'
import core.clone.Clone
import core.iter
import core.iter.Iterator

type Token {}
type Tokens {}
extend Tokens implements Iterator {
    type Item = Token
    mut fn next(): Token? { none }
}
extend Tokens implements Clone { fn clone(): Tokens { Tokens() } }
fn needs_clone<T: Clone>(): Unit {}

fn main(): i32 {
    needs_clone<iter.Peekable<Tokens>>()
    0
}
