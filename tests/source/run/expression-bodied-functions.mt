fn double(value: i32): i32 => value * 2
fn inferred(value: i32) => value * 2

interface Twice {
    fn amount(): i32;
    fn twice(): i32 => self.amount() * 2;
}

type Number {
    n: i32
    fn twice_direct(): i32 => self.n * 2
}

extend Number implements Twice {
    fn amount(): i32 { self.n }
}

fn main(): i32 {
    let value = Number(21)
    if double(21) == 42 && inferred(21) == 42 &&
       value.twice_direct() == 42 && value.twice() == 42 {
        0
    } else {
        1
    }
}
