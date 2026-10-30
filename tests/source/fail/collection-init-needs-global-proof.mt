// expect-error: type 5:5 no constructor of 'List' accepts this argument shape
import alloc.alloc.Allocator
import alloc.vec.List
fn make<A: Allocator>(): List<i32, A> {
    List<i32, A>()
}
fn main() { 0 }
