macro select {
    ($scrutinee: expression, $value: expression) => {
        match $scrutinee { item => $value }
    };
}

macro plus_one {
    ($value: expression) => { $value + 1 };
}

macro from_definition {
    () => { definition_answer() };
}

fn definition_answer(): i32 { 40 }

module nested {
    fn definition_answer(): i32 { 1 }
    pub fn call(): i32 { from_definition!() }
}

fn main(): i32 {
    let item = 40
    let selected = select!(0, item)
    let scaled = 2 * plus_one!(3)
    if selected != 40 || scaled != 8 || nested.call() != 40 { return 1 }
    0
}
