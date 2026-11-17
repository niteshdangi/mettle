static VALUE: i32 = 42
static VIEW: read i32 from static = read VALUE

fn first(): read i32 from static { VIEW }
fn second(): read i32 from static { first() }

fn main(): i32 {
    if *second() == 42 { 0 } else { 1 }
}
