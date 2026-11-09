// expect-error: ownership 7:5 cannot store a view of local storage into caller-owned storage

type H<T> { v: T }
fn put<T>(mut h: H<T>, take x: T): Unit { h.v = x }
fn bad(mut h: H<read i32>): Unit {
    let x = 5
    put(h, read x)
}
fn main() { 0 }
