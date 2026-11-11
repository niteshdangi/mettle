// profiles: debug release
macro generate {
    ($captured:ident) => {
        fn mixed<$captured, T>(take left: $captured, take right: T): T {
            right
        }
        fn apply<$captured, T: for<region r> fn(read i32 from r): read i32 from r>(
            take ignored: $captured, read operation: T,
            read value: i32): read i32 from value {
            operation(value)
        }
    };
}
generate!(T)

fn identity<region r>(read value: i32 from r): read i32 from r { read value }

fn main(): i32 {
    if mixed(left: 1u8, right: 7i32) != 7 { return 1 }
    let value = 7
    if *apply(0u8, identity, value) == 7 { 0 } else { 2 }
}
