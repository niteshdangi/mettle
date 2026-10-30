// expect-error: ownership 6:15 cannot store a view of local storage into caller-owned storage

type H<T> { v: T }
fn bad(slot: mut H<read i32>): Unit {
    let x = 5
    let old = core.mem.replace(slot, H(read x))
}
fn main() { 0 }
