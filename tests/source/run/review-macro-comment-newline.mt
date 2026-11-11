macro keep { ($body:block) => { $body }; }
fn main(): i32 {
    keep!({
        let x = 1 /*
        */ let y = 2
        x + y
    }) - 3
}
