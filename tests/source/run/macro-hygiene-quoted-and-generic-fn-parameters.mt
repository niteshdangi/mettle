// profiles: debug release
// Parameters of macro-generated functions with a backticked name or generic
// parameters are binders like any other: a body use of the parameter resolves
// even when another generated function binds the same name.
import core.clone.Clone

interface Make<T>: Sized { static fn `from`(value: take T): Self; }

macro generated {
    ($target:ident; $($source:ident),*) => {
        $(
            extend $target implements Make<$source> {
                static fn `from`(value: take $source): $target { value as $target }
            }
        )*
        fn twice<T: Clone>(value: read T): (T, T) { (value.clone(), value.clone()) }
        fn plain(value: $target): $target { value }
    };
}

generated!(u32; u8, u16)

fn main(): i32 {
    if u32.(Make<u8>).`from`(7u8) != 7u32 { return 1 }
    if u32.(Make<u16>).`from`(9u16) != 9u32 { return 2 }
    let (left, right) = twice(read 5i64)
    if left != 5i64 || right != 5i64 { return 3 }
    if plain(4u32) != 4u32 { return 4 }
    0
}
