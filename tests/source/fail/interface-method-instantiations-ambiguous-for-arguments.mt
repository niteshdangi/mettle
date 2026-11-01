// expect-error: type 20:5 ambiguous interface method
// Argument types do not separate the two instantiations, so the call stays
// ambiguous.
interface Note<T> {
    fn note<V>(value: V): i32;
}

type Pad { size: i32 }

extend Pad implements Note<i32> {
    fn note<V>(value: V): i32 { 1 }
}

extend Pad implements Note<bool> {
    fn note<V>(value: V): i32 { 2 }
}

fn main(): i32 {
    let pad = Pad(0)
    pad.note(3)
}
