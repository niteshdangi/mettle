type Element<region r> { value: read i32 from r }
type Brand<region r> { value: read i32 from r }
type Pair<region s> {
    queue: core.cell.Cell<Element<region s>>;
    brand: core.cell.Cell<Brand<region s>>
}
fn main(): i32 {
    let value = 42
    let pair = Pair(
        core.cell.Cell.new(Element(read value)),
        core.cell.Cell.new(Brand(read value))
    )
    0
}
