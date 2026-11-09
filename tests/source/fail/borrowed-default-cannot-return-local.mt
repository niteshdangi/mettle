// expect-error: region 6:5 view region or invariant payload
type Holder<region r> { value: (read i32 from r)? }

fn invalid<region r>(): Holder<region r> {
    let value = 7
    return Holder(present(read value))
}

fn main(): i32 { 0 }
