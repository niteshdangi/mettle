import core.default.Default
import alloc.string
import alloc.vec

@derive(Default)
type Point { x: i32; y: i32 }

@derive(Default)
type Config { level: u8; enabled: bool; origin: Point; extra: i32?; ratio: f64 }

@derive(Default)
type Wrap<T> { value: T; count: usize }

type Manual { level: i32 }
extend Manual implements Default {
    static fn default(): Manual { Manual(level: 7) }
}

@derive(Default)
type Holder { manual: Manual; pair: (i32, bool); name: string.String; items: vec.Vec<i32> }

@derive(Default)
type Marker {}

fn make<T: Default>(): T { T.(Default).default() }

fn main(): i32 {
    let p = make<Point>()
    if p.x != 0 || p.y != 0 { return 1 }
    let c = make<Config>()
    if c.level != 0u8 || c.enabled || c.origin.x != 0 || c.ratio != 0.0f64 { return 2 }
    match c.extra { present(v) => { return 3 }, none => {} }
    let w = make<Wrap<i32>>()
    if w.value != 0 || w.count != 0usize { return 4 }
    let nested = make<Wrap<Wrap<bool>>>()
    if nested.value.value || nested.count != 0usize { return 5 }
    let h = make<Holder>()
    if h.manual.level != 7 || h.pair.0 != 0 || h.pair.1 { return 6 }
    if h.name.len() != 0usize || h.items.len() != 0usize { return 7 }
    let m = make<Manual>()
    if m.level != 7 { return 8 }
    let marker = make<Marker>()
    0
}
