interface Root { fn value(): i32 }
interface Left: Root {}
interface Right: Root {}
interface Diamond: Left + Right {}
interface Other { fn value(): i32 }

type Number { value: i32 }
extend Number implements Root {
    fn value(): i32 { self.value }
}
extend Number implements Left {}
extend Number implements Right {}
extend Number implements Diamond {}
extend Number {
    fn first(): i32 { self.value + 1 }
    fn second(): i32 { self.value + 2 }
}

type Separate {}
extend Separate implements Other {
    fn value(): i32 { 99 }
}
extend Separate {
    fn first(): i32 { 100 }
}

fn inherited<T: Diamond>(read number: T): i32 { number.value() }

fn main(): i32 {
    let number = Number(10)
    let other = Separate()
    if inherited(read number) == 10 &&
       number.value() == 10 &&
       number.first() == 11 &&
       number.second() == 12 &&
       other.value() == 99 &&
       other.first() == 100 { 0 } else { 1 }
}
