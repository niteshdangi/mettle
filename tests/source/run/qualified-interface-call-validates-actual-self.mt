interface Value: Sized {
    static fn value(): Self;
}

extend i32 implements Value {
    static fn value(): i32 { 42 }
}

fn get<T: Value>(): T { T.(Value).value() }

fn main(): i32 { get<i32>() - 42 }
