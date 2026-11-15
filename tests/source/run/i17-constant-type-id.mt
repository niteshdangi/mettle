// profiles: debug release
import core.any.{TypeId, type_id}
import core.clone.Clone
import core.cmp.{PartialEq, PartialOrd, Ord}

alias Bound = for<region r> fn(read (read i32 from r)): read i32 from r
alias Renamed = for<region s> fn(read (read i32 from s)): read i32 from s

const INTEGER: TypeId = TypeId.of<i32>()
const WIDER: TypeId = TypeId.of<i64>()
const SLICE: TypeId = TypeId.of<[i32]>()
const BOUND: TypeId = TypeId.of<Bound>()
const RENAMED: TypeId = type_id<Renamed>()

fn main(): i32 {
    if INTEGER != type_id<i32>() || INTEGER == WIDER { return 1 }
    if SLICE != TypeId.of<[i32]>() { return 2 }
    if BOUND != RENAMED { return 3 }
    let cloned = INTEGER.clone()
    if cloned != INTEGER { return 4 }
    if cloned.partial_cmp(INTEGER) != present(core.cmp.Ordering.Equal) { return 5 }
    if cloned.cmp(INTEGER) != core.cmp.Ordering.Equal { return 6 }
    if core.hash.hash_one(cloned) != core.hash.hash_one(INTEGER) { return 7 }
    if (INTEGER < WIDER) != INTEGER.cmp(WIDER).is_lt() { return 8 }
    0
}
