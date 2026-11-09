copy type Item { value: i32 }

fn bump(mut item: Item, amount: i32 = 1): Unit { item.value += amount }
fn inspect(read item: Item): i32 { item.value }
fn transfer<region r>(take view: read Item from r): read Item from r { view }
fn pair_sum(read (left, right): (i32, i32)): i32 { left + right }
fn preserve<T>(take value: Outcome<T, i32>): Outcome<T, i32> { take value }
fn attempt(value: i32): i32 throws i32 {
    if value < 0 { throw 7 }
    value + 1
}

fn main(): i32 {
    var item = Item(1)
    bump(item)
    if inspect(item) != 2 { return 1 }
    let update: fn(mut Item, i32): Unit = bump
    update(mut item, 2)
    let modify = fn(mut value: Item): Unit { value.value += 3 }
    modify(mut item)
    let view = transfer(read item)
    if view.value != 7 || pair_sum((2, 3)) != 5 { return 2 }

    let saved: Outcome<i32, i32> = capture attempt(4)
    match take saved {
        success(value) => { if value != 5 { return 3 } },
        failure(_) => { return 4 }
    }
    let nested: Outcome<Outcome<i32, i32>, i32> =
        success(preserve(capture attempt(-1)))
    match take nested {
        success(result) => match take result {
            failure(error) => { if error != 7 { return 5 } },
            success(_) => { return 6 }
        },
        failure(_) => { return 7 }
    }
    let optional: Outcome<i32, i32>? = present(success(9))
    match take optional {
        present(result) => match take result {
            success(value) => { if value != 9 { return 8 } },
            failure(_) => { return 9 }
        },
        none => { return 10 }
    }
    let call: fn(i32): i32 throws i32 = attempt
    match capture call(10) {
        success(value) => { if value != 11 { return 11 } },
        failure(_) => { return 12 }
    }
    0
}
