module first {
    pub macro value { () => { 20 }; }
    pub fn get(): i32 { value!() }
}

module second {
    macro value { () => { 22 }; }
    pub fn get(): i32 { value!() }
}

fn main(): i32 {
    first.get() + second.get() - 42
}
