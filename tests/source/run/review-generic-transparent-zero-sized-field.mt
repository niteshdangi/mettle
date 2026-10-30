
@layout(transparent)
copy type Wrapper<T:Copy> { value:T; other:u32 }
fn main() {
    let value = Wrapper((),42u32)
    if value.other == 42u32 && core.mem.size_of<Wrapper<Unit>>() == 4usize { 0 } else { 1 }
}
