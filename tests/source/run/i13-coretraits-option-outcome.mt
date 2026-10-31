import core.option
import core.outcome

fn main(): i32 {
    if true.then_some(7).unwrap() != 7 { return 1 }
    if false.then_some(7).is_present() { return 2 }

    var option_value = present(21i32)
    var option_iter = option_value.iter()
    if option_iter.len() != 1usize { return 21 }
    match take option_iter.next_back() {
        present(value) => { if *value != 21 { return 22 } },
        none => { return 22 }
    }
    if option_iter.len() != 0usize { return 23 }
    {
        var option_iter_mut = option_value.iter_mut()
        match take option_iter_mut.next() {
            present(value) => { *value = 24 },
            none => { return 24 }
        }
    }
    if option_value.unwrap() != 24 { return 25 }
    var inserted = present(26i32)
    {
        let target = inserted.insert(27i32)
        *target = 28
    }
    if inserted.unwrap() != 28 { return 29 }
    match take present(30i32).zip(present(31i32)) {
        present((left, right)) => { if left != 30 || right != 31 { return 32 } },
        none => { return 32 }
    }
    let missing_zip: i32? = none
    if present(33i32).zip(missing_zip).is_present() { return 34 }

    var outcome_value: (i32 throws i32) = success(35i32)
    var outcome_iter = outcome_value.iter()
    if outcome_iter.len() != 1usize { return 36 }
    match take outcome_iter.next_back() {
        present(value) => { if *value != 35 { return 37 } },
        none => { return 37 }
    }
    if outcome_iter.len() != 0usize { return 38 }
    {
        var outcome_iter_mut = outcome_value.iter_mut()
        match take outcome_iter_mut.next() {
            present(value) => { *value = 39 },
            none => { return 39 }
        }
    }
    if outcome_value.unwrap() != 39 { return 40 }
    let failed_iter_value: (i32 throws i32) = failure(41i32)
    if failed_iter_value.iter().len() != 0usize { return 42 }

    match present(3i32).xor(none) {
        present(value) => { if value != 3 { return 3 } },
        none => { return 3 }
    }
    if present(3i32).xor(present(4i32)).is_present() { return 4 }
    match present(present(5i32)).flatten() {
        present(value) => { if value != 5 { return 5 } },
        none => { return 5 }
    }
    if !present(6i32).is_some_and(fn(value: take i32): bool { value == 6 }) {
        return 6
    }
    let absent_for_none_or: i32? = none
    if !absent_for_none_or.is_none_or(fn(value: take i32): bool { value == 0 }) { return 7 }
    if present(8i32).map_or_else(
        fn(): i32 { 0 },
        fn(value: take i32): i32 { value }
    ) != 8 {
        return 8
    }
    let absent_for_map: i32? = none
    if absent_for_map.map_or_default(fn(value: take i32): i32 { value }) != 0 { return 9 }
    let absent_for_default: i32? = none
    if absent_for_default.unwrap_or_default() != 0 { return 10 }

    let (left, right) = present((11i32, 12i32)).unzip()
    if left.unwrap() != 11 || right.unwrap() != 12 { return 11 }

    let failure_value: (i32 throws i32) = failure(13i32)
    if failure_value.map_or_else(
        fn(error: take i32): i32 { error },
        fn(value: take i32): i32 { value }
    ) != 13 {
        return 12
    }
    let failure_value: (i32 throws i32) = failure(14i32)
    if failure_value.unwrap_or_default() != 0 { return 13 }
    let failure_value: (i32 throws i32) = failure(15i32)
    if failure_value.expect_failure("expected failure") != 15 { return 14 }

    let success_value: (i32 throws i32) = success(16i32)
    let combined: (i32 throws i32) = success_value.and(failure(17i32))
    match combined {
        success(value) => { return 15 },
        failure(error) => { if error != 17 { return 15 } }
    }
    let option_result: (i32 throws i32)? = present(success(18i32))
    match take option_result.transpose() {
        success(value) => match value {
            present(item) => { if item != 18 { return 16 } },
            none => { return 16 }
        },
        failure(error) => { return 16 }
    }
    let result_option: (i32? throws i32) = success(present(19i32))
    match take result_option.transpose() {
        present(success(item)) => { if item != 19 { return 17 } },
        present(failure(error)) => { return 17 },
        none => { return 17 }
    }
    let failed_option: (i32 throws i32)? = present(failure(20i32))
    match take failed_option.transpose() {
        success(value) => { return 18 },
        failure(error) => { if error != 20 { return 18 } }
    }
    let empty_option: (i32 throws i32)? = none
    match take empty_option.transpose() {
        success(value) => { if value.is_present() { return 19 } },
        failure(error) => { return 19 }
    }
    let failed_outcome: (i32? throws i32) = failure(21i32)
    match take failed_outcome.transpose() {
        present(success(value)) => { return 20 },
        present(failure(error)) => { if error != 21 { return 20 } },
        none => { return 20 }
    }
    0
}
