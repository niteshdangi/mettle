// profiles: debug release
import alloc.boxed
import alloc.boxed.Box
import core.any.Any

fn identity(take value: Box<any Any>): Box<any Any> { value }

fn main(): i32 {
    let erased: Box<any Any> = identity(boxed.new(42i32))
    match take erased.downcast<i32>() {
        success(value) => { *value.get() - 42 },
        failure(_) => 1
    }
}
