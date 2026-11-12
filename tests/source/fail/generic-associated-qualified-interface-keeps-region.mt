// profiles: debug release
// expect-error: region 23:18 interface bound does not hold after region inference
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
type Sum {}
extend<region r> Sum implements FromItems<Borrowed<region r, i32>> {
    static fn from_iter<I: OwnedIterable<Item = Borrowed<region r, i32>>>(take items: I): Sum { Sum() }
}
fn main(): i32 {
    var number = 7i32
    let item = Borrowed.Borrowed(read number)
    let result = Sum.(FromItems<Borrowed<region static, i32>>).from_iter(Pack(take item))
    0
}
