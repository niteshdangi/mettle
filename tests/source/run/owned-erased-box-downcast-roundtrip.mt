// profiles: debug release
import alloc.boxed
import alloc.boxed.Heap
import core.any.Any

fn identity(take value: Heap<any Any>): Heap<any Any> { value }

fn main(): i32 {
    let erased: Heap<any Any> = identity(boxed.new(42i32))
    match take erased.downcast<i32>() {
        success(value) => { *value.get() - 42 },
        failure(_) => 1
    }
}
