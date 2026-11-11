const VALUE: i32 = 7

macro definition_value { () => { VALUE }; }
macro captured_value { ($value:expr) => { $value }; }
macro explicit_value { () => { $capture(VALUE) }; }

const fn combined(): i32 {
    let VALUE = 9i32
    definition_value!() * 100 + captured_value!(VALUE) * 10 + explicit_value!()
}

const RESULT: i32 = combined()
fn main(): i32 { RESULT - 799 }
