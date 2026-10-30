// expect-error: attribute 5:25 object layout cannot be established

@layout(transparent)
copy type Wrapper<T:Copy> { value:T; other:u32 }
fn main() { let value = Wrapper(1u8,2u32); 0 }
