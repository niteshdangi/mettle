// profiles: debug release
import core.default.Default

type Empty<region r> { value: (read i32 from r)? }
extend<region r> Empty<region r> implements Default {
    static fn default(): Empty<region r> { Empty(none) }
}

fn make<region r>(): Empty<region r> { Empty(none) }
fn default_of<T: Default>(): T { T.(Default).default() }

fn check<region r>(read anchor: i32 from r): i32 {
    let direct: Empty<region r> = make()
    let defaulted: Empty<region r> = default_of<Empty<region r>>()
    let qualified = Empty<region r>.(Default).default()
    if direct.value.is_present() || defaulted.value.is_present() ||
       qualified.value.is_present() { return 1 }
    0
}

fn main(): i32 {
    let anchor = 7
    check(anchor)
}
