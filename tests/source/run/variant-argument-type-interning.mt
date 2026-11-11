enum Value { Number(i32) }

fn main(): i32 {
    let value = Value.Number({
        let _: (i32, i32) = (0, 0)
        let _: (i32, i32, i32) = (0, 0, 0)
        let _: (i32, i32, i32, i32) = (0, 0, 0, 0)
        42
    })
    match value { Value.Number(number) => number - 42 }
}
