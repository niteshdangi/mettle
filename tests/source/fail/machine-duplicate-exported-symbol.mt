// expect-error: signature 5:12 conflicting external symbol
@export_name("mettle_duplicate_machine_symbol")
extern "C" fn first(): i32 { 1 }
@export_name("mettle_duplicate_machine_symbol")
extern "C" fn second(): i32 { 2 }
fn main(): i32 { 0 }
