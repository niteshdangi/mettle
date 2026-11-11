// profiles: debug release
module definitions {
    type Payload { pub value: i32 }
    fn secret(): i32 { 7 }
    pub macro payload {
        ($value:expr) => { Payload(value: $value + secret()) };
    }
}

fn evaluate<Payload>(take ignored: Payload): i32 {
    definitions.payload!(2i32).value
}

fn main(): i32 { evaluate(0u8) - 9 }
