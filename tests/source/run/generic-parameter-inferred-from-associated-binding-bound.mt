
module core { pub module iter { pub interface Iterator { type Item; mut fn next(): Self.Item?; } } }
import core.iter.Iterator
type Counter { n: i32; max: i32 }
extend Counter implements Iterator {
    type Item = i32
    mut fn next(): i32? {
        if self.n < self.max { let v = self.n; self.n += 1; present(v) } else { none }
    }
}
fn sum<T, I: Iterator<Item = T>>(take it: I, take first: T): T {
    var iter = it
    var acc = first
    while true { match take iter.next() { present(x) => { acc = x }, none => { break } } }
    acc
}
interface QueryNumber { fn number(): i32; }
extend i32 implements QueryNumber { fn number(): i32 { self } }
extend i64 implements QueryNumber { fn number(): i32 { self as i32 } }
interface QueryView<Q: unsized> { fn get(): read Q from self; }
interface QueryKey<Q: unsized> { fn offset(): i32; }
type Endpoint<T> { value: T }
type DualKey {}
extend DualKey implements QueryKey<i32> { fn offset(): i32 { 1 } }
extend DualKey implements QueryKey<i64> { fn offset(): i32 { 2 } }
extend<T> Endpoint<T> implements QueryView<T> {
    fn get(): read T from self { read self.value }
}
extend<T> (Endpoint<T>, Endpoint<T>) implements QueryView<T> {
    fn get(): read T from self { read self.0.value }
}
fn query<K, Q: QueryNumber + unsized, R: QueryView<Q>>(
    read key: K, read bounds: R
): i32 where K: QueryKey<Q> {
    K.(QueryKey<Q>).offset(key) + bounds.get().number()
}
interface QueryEq<Rhs: unsized = Self> { fn same(read other: Rhs): bool; }
interface QueryOrder<Rhs: unsized = Self>: QueryEq<Rhs> {
    fn compare(read other: Rhs): i32;
    fn less(read other: Rhs): bool { self.compare(other) < 0 }
}
type SingleKey { value: i32 }
extend SingleKey implements QueryKey<i32> { fn offset(): i32 { self.value } }
extend SingleKey implements QueryEq {
    fn same(read other: SingleKey): bool { self.value == other.value }
}
extend SingleKey implements QueryOrder {
    fn compare(read other: SingleKey): i32 { self.value - other.value }
}
enum QueryBound<T> { Included(T); Unbounded }
interface QueryRange<Q: unsized> {}
extend<T> (QueryBound<T>, QueryBound<T>) implements QueryRange<T> {}
extend<region r, T: unsized>
    (QueryBound<read T from r>, QueryBound<read T from r>)
    implements QueryRange<T> {}
fn rangeQuery<K, Q: unsized, R: QueryRange<Q>>(
    read key: K, take bounds: R
): i32 where K: QueryKey<Q> { K.(QueryKey<Q>).offset(key) }
fn main(): i32 {
    let last = sum(Counter(0, 4), 0)
    if last != 3 { return 1 }
    let key = DualKey()
    if query(read key, Endpoint(7i32)) != 8 { return 2 }
    if query(read key, (Endpoint(9i64), Endpoint(10i64))) != 11 { return 3 }
    let single = SingleKey(1)
    if !single.less(SingleKey(2)) { return 4 }
    if rangeQuery(read single, (QueryBound.Unbounded, QueryBound.Included(7i32))) != 1 { return 5 }
    if rangeQuery(read single, (QueryBound.Included(7i32), QueryBound.Unbounded)) != 1 { return 6 }
    0
}
