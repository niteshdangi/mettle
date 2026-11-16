// expect-exit: 0
// An interface associated constant of aggregate type is produced by its
// implementation, reached through a bound, directly, and through a generic
// implementation.

interface Origin { const VALUE: Self; }

copy type Point { x: i32; y: i32 }
extend Point implements Origin { const VALUE = Point(20, 22) }

copy type Wrapper<T> { inner: T }
extend<T: Origin> Wrapper<T> implements Origin {
    const VALUE = Wrapper(T.(Origin).VALUE)
}

fn origin<T: Origin>(): T { T.(Origin).VALUE }

fn main(): i32 {
    let direct = Point.(Origin).VALUE
    if direct.x != 20 || direct.y != 22 { return 1 }
    let bound: Point = origin()
    if bound.x + bound.y != 42 { return 2 }
    let wrapped: Wrapper<Point> = origin()
    if wrapped.inner.x != 20 || wrapped.inner.y != 22 { return 3 }
    0
}
