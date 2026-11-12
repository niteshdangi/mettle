// profiles: debug release
import core.iter.{FromItems, OwnedIterable, Once, once}

interface Family { type Owner; }
extend i32 implements Family { type Owner = i32 }
enum Borrowed<region r, T: Family + unsized> {
    Borrowed(read T from r), Owned(T.(Family).Owner)
}
type Pack<T> { value: T }
extend<T> Pack<T> implements OwnedIterable {
    type Item = T
    type IntoIter = Once<T>
    fn into_iter(receiver take self: Self): Once<T> { once(take self.value) }
}
type Sum { value: i32 }
extend<region r> Sum implements FromItems<Borrowed<region r, i32>> {
    static fn from_iter<I: OwnedIterable<Item = Borrowed<region r, i32>>>(take items: I): Sum {
        var total = 0i32
        for item in take items {
            match item {
                Borrowed.Borrowed(value) => { total += *value },
                Borrowed.Owned(value) => { total += value }
            }
        }
        Sum(total)
    }
}
static ROOT: i32 = 7i32
fn sum_for<region r>(read value: i32 from r): i32 {
    let item: Borrowed<region r, i32> = Borrowed.Borrowed(read value)
    Sum.(FromItems<Borrowed<region r, i32>>).from_iter(Pack(take item)).value
}
fn main(): i32 {
    let item: Borrowed<region static, i32> = Borrowed.Borrowed(read ROOT)
    let result = Sum.(FromItems<Borrowed<region static, i32>>).from_iter(Pack(take item))
    var number = 5i32
    let owned: Borrowed<region static, i32> = Borrowed.Owned(3i32)
    let other = Sum.(FromItems<Borrowed<region static, i32>>).from_iter(Pack(take owned))
    if result.value == 7i32 && sum_for(read number) == 5i32 && other.value == 3i32 {
        0
    } else { 1 }
}
