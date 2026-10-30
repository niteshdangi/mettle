import core.clone.Clone
import core.cmp.{PartialEq, Eq, PartialOrd, Ord, Ordering}
import core.hash.Hash

@derive(Clone, PartialEq, Eq, PartialOrd, Ord)
type Pair { a: i32; b: i32 }

@derive(Clone, PartialEq, PartialOrd)
enum Shape { Dot, Line(i32, i32), Box { w: i32, h: i32 } }

@derive(Clone, PartialEq)
type Wrap<T> { value: T }

fn main(): i32 {
    let p = Pair(1, 2)
    let q = p.clone()
    if !(p == q) { return 1 }
    if !(Pair(1, 3) > p) { return 2 }
    if p.cmp(read Pair(1, 2)) != Ordering.Equal { return 3 }
    let s = Shape.Line(1, 2)
    if !(s.clone() == Shape.Line(1, 2)) { return 4 }
    if s == Shape.Dot { return 5 }
    let b = Shape.Box(w: 1, h: 1)
    if !(Shape.Dot < b) { return 6 }
    if !(Wrap(5).clone() == Wrap(5)) { return 7 }
    0
}
