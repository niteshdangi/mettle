import core.any
import core.cmp
import core.cmp.{Ord, Ordering, PartialOrd}
import core.clone.Clone
import core.convert
import core.convert.{From, TryFrom}
import core.hash.Hash
import core.hash.hash_one
import core.ops.ControlFlow

const IDENTITY: i32 = core.convert.identity(41i32)

type Ranked {
    rank: i32
    id: i32
}

type ConvertSource { value: i32 }
type ConvertTarget { value: i32 }
extend ConvertTarget implements From<ConvertSource> {
    static fn from(take value: ConvertSource): ConvertTarget { ConvertTarget(value.value) }
}

fn require_never_traits<T: Clone + Ord + Hash>() {}
fn require_never_from<T: From<Never>>() {}

fn check_control_flow(): i32 {
    let continued = ControlFlow.Continue(7i32)
    if !continued.is_continue() || continued.is_break() { return 12 }
    let duplicate = continued.clone()
    if duplicate != continued || hash_one(read duplicate) != hash_one(read continued) { return 13 }
    if ControlFlow.Continue(7i32) == ControlFlow.Break(7i32) { return 14 }
    match take ControlFlow.Break(9i32).break_ok() {
        success(value) => { if value != 9 { return 15 } },
        failure(_) => { return 16 }
    }
    match take ControlFlow.Continue(11i32).continue_ok() {
        success(value) => { if value != 11 { return 17 } },
        failure(_) => { return 18 }
    }
    0
}

fn main(): i32 {
    require_never_traits<Never>()
    require_never_from<core.array.TryFromSliceError>()
    require_never_from<core.num.TryFromIntError>()
    if Ordering.Less as i8 != -1i8 || Ordering.Equal as i8 != 0i8 ||
       Ordering.Greater as i8 != 1i8 { return 19 }
    let control_flow_status = check_control_flow()
    if control_flow_status != 0 { return control_flow_status }
    let type_id = core.any.type_id<i32>()
    let type_id_copy = type_id.clone()
    if type_id_copy != type_id || type_id.cmp(read type_id_copy) != Ordering.Equal { return 9 }
    if type_id.partial_cmp(read type_id_copy) != present(Ordering.Equal) { return 10 }
    if hash_one(read type_id) != hash_one(read type_id_copy) { return 11 }
    if IDENTITY != 41 { return 1 }
    let value = core.convert.identity(Ranked(7, 9))
    if value.rank != 7 || value.id != 9 { return 2 }

    match take ConvertTarget.(TryFrom<ConvertSource>).try_from(ConvertSource(17)) {
        success(converted) => { if converted.value != 17 { return 7 } },
        failure(_) => { return 8 }
    }

    var comparisons = 0
    let first_min = cmp.min_by(
        Ranked(3, 1),
        Ranked(3, 2),
        fn(read left: Ranked, read right: Ranked): Ordering {
            comparisons += 1
            left.rank.cmp(right.rank)
        }
    )
    if first_min.id != 1 || comparisons != 1 { return 3 }

    let last_max = cmp.max_by(
        Ranked(3, 1),
        Ranked(3, 2),
        fn(read left: Ranked, read right: Ranked): Ordering {
            comparisons += 1
            left.rank.cmp(right.rank)
        }
    )
    if last_max.id != 2 || comparisons != 2 { return 4 }

    var key_calls = 0
    let first_key_min = cmp.min_by_key(
        Ranked(5, 3),
        Ranked(5, 4),
        fn(read value: Ranked): i32 {
            key_calls += 1
            value.rank
        }
    )
    if first_key_min.id != 3 || key_calls != 2 { return 5 }

    let last_key_max = cmp.max_by_key(
        Ranked(5, 3),
        Ranked(5, 4),
        fn(read value: Ranked): i32 {
            key_calls += 1
            value.rank
        }
    )
    if last_key_max.id != 4 || key_calls != 4 { return 6 }
    0
}
