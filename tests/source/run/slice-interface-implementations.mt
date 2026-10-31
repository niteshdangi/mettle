import alloc.vec.List

interface FirstElement {
    type Item;
    fn head(receiver self: read Self): Self.Item;
}

extend<T: Copy> [T] implements FirstElement {
    type Item = T
    fn head(receiver self: read Self): T { self[0] }
}

fn first<C: FirstElement + unsized>(values: read C): C.(FirstElement).Item {
    values.head()
}

fn projected(values: read [i32]): [i32].(FirstElement).Item {
    values.head()
}

fn main(): i32 {
    let data = [42, 7]
    let slice: read [i32] = read data
    if slice.head() != 42 { return 1 }
    if first(slice) != 42 { return 2 }
    if projected(slice) != 42 { return 3 }
    if [i32].(FirstElement).head(slice) != 42 { return 4 }

    var values: List<i32> = alloc.vec.new<i32>()
    values.push(9)
    if values.head() != 9 { return 5 }
    0
}
