// profiles: debug release
// expect-error-count: 1
// expect-error: region 7:55 borrowed source does not outlive the required region
import core.any
import core.any.TypeId

fn view_id<region r>(read view: i32 from r): TypeId { any.type_id<read i32 from r>() }

fn main(): i32 {
    let number = 7
    let found = view_id(read number)
    0
}
