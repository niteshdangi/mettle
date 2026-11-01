import alloc.borrow.Cow
import alloc.vec.List
import core.convert.From

fn copy_borrowed<region r>(items: read [i32] from r): i32 {
    let cow: Cow<region r, i32> = Cow.Borrowed(read items)
    if !cow.is_borrowed() || cow.as_ref().len() != 3usize { return 5 }
    var list = List<i32>.(From<Cow<region r, i32>>).`from`(cow)
    if list.len() != 3usize { return 1 }
    if list[0usize] != 4 || list[1usize] != 7 || list[2usize] != 9 { return 2 }
    list[0usize] = 99
    0
}

fn move_owned<region r>(anchor: read i32 from r): i32 {
    let _ = anchor
    var items = alloc.vec.new<i32>()
    items.push(12)
    items.push(15)
    let cow: Cow<region r, i32> = Cow.Owned(items)
    if cow.is_borrowed() || cow.as_ref()[1usize] != 15 { return 6 }
    let list = List<i32>.(From<Cow<region r, i32>>).`from`(cow)
    if list.len() != 2usize { return 3 }
    if list[0usize] != 12 || list[1usize] != 15 { return 4 }
    0
}

fn main(): i32 {
    let values: [i32; 3] = [4, 7, 9]
    let view: read [i32] = read values
    let borrowed = copy_borrowed(view)
    if borrowed != 0 { return borrowed }
    if values[0usize] != 4 || values[1usize] != 7 { return 7 }
    move_owned(read values[0usize])
}
