// profiles: debug release
import core.borrow.{AsMut, AsRef, Borrow}
import core.convert.TryFrom

fn viewed<T, const N: usize>(read items: [T; N]): read [T] from items { [T; N].(AsRef<[T]>).as_ref(items) }
fn borrowed<T, const N: usize>(read items: [T; N]): read [T] from items { [T; N].(Borrow<[T]>).borrow(items) }
fn mutated<T, const N: usize>(mut items: [T; N]): mut [T] from items { [T; N].(AsMut<[T]>).as_mut(items) }

fn main(): i32 {
    var items = [1, 2, 3]
    let twin = items
    items[0usize] = 9
    if twin[0usize] != 1 || items[0usize] != 9 { return 1 }
    if viewed(items).len() != 3usize || borrowed(items)[2usize] != 3 { return 2 }
    mutated(mut items)[1usize] = 8
    if items[1usize] != 8 { return 3 }

    var total = 0
    for value in read items { total += value }
    for value in mut items { value += 1 }
    for value in items { total += value }
    if total != 20 + 23 { return 4 }

    var storage = [4, 5, 6]
    let window: mut [i32] = mut storage
    match [i32; 3].(TryFrom<mut [i32]>).try_from(take window) {
        success(copied) => { if copied[2usize] != 6 { return 5 } },
        failure(error) => { return 6 }
    }

    0
}
