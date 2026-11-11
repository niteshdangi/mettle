// profiles: debug release
macro generated {
    () => {
        type Counter {
            pub value: i32
            drop { self.value = 0 }
        }
    };
}
generated!()

fn main(): i32 {
    let counter = Counter(42)
    counter.value - 42
}
