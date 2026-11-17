interface Number {
    fn number(): i32;
}

extend i32 implements Number {
    fn number(): i32 { self }
}

fn inspect<T: Number + Copy>(value: T): i32 where T = T {
    value.number()
}

fn main(): i32 {
    if inspect(42) == 42 { 0 } else { 1 }
}
