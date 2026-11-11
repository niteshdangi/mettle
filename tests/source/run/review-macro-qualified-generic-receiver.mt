interface Make: Sized { static fn make(): Self; }
extend i32 implements Make { static fn make(): i32 { 42 } }

macro generate {
    () => {
        fn create<T: Make>(): T { T.(Make).make() }
    };
}
generate!()

fn main(): i32 {
    if create<i32>() == 42 { 0 } else { 1 }
}
