import core.cmp.Ordering
import core.default.Default
import core.fmt.Error
import core.hash

fn main(): i32 {
    let first = Error()
    let cloned = first.clone()
    let defaulted = Error.(Default).default()

    if first != cloned { return 1 }
    if first != defaulted { return 2 }
    if first.partial_cmp(defaulted) != present(Ordering.Equal) { return 3 }
    if first.cmp(defaulted) != Ordering.Equal { return 4 }
    if hash.hash_one(read first) != hash.hash_one(read defaulted) { return 5 }
    0
}
