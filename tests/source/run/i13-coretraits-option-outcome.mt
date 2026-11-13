import core.option
import core.outcome

fn main(): i32 {
    if true.then_present(7).unwrap() != 7 { return 1 }
    if false.then_present(7).is_present() { return 2 }

    match present(3i32).xor(none) {
        present(value) => { if value != 3 { return 3 } },
        none => { return 3 }
    }
    if present(3i32).xor(present(4i32)).is_present() { return 4 }
    match present(present(5i32)).flatten() {
        present(value) => { if value != 5 { return 5 } },
        none => { return 5 }
    }
    if !present(6i32).is_present_and(fn(take value: i32): bool { value == 6 }) {
        return 6
    }
    let absent_for_none_or: i32? = none
    if !absent_for_none_or.is_none_or(fn(take value: i32): bool { value == 0 }) { return 7 }
    if present(8i32).map_or_else(
        fn(): i32 { 0 },
        fn(take value: i32): i32 { value }
    ) != 8 {
        return 8
    }
    let absent_for_map: i32? = none
    if absent_for_map.map_or_default(fn(take value: i32): i32 { value }) != 0 { return 9 }
    let absent_for_default: i32? = none
    if absent_for_default.unwrap_or_default() != 0 { return 10 }

    let (left, right) = present((11i32, 12i32)).unzip()
    if left.unwrap() != 11 || right.unwrap() != 12 { return 11 }

    let failure_value: (Outcome<i32, i32>) = failure(13i32)
    if failure_value.map_or_else(
        fn(take error: i32): i32 { error },
        fn(take value: i32): i32 { value }
    ) != 13 {
        return 12
    }
    let failure_value: (Outcome<i32, i32>) = failure(14i32)
    if failure_value.unwrap_or_default() != 0 { return 13 }
    let failure_value: (Outcome<i32, i32>) = failure(15i32)
    if failure_value.expect_failure("expected failure") != 15 { return 14 }

    let success_value: (Outcome<i32, i32>) = success(16i32)
    let combined: (Outcome<i32, i32>) = success_value.and(failure(17i32))
    match combined {
        success(value) => { return 15 },
        failure(error) => { if error != 17 { return 15 } }
    }
    let option_result: (Outcome<i32, i32>)? = present(success(18i32))
    match take option_result.transpose() {
        success(value) => match value {
            present(item) => { if item != 18 { return 16 } },
            none => { return 16 }
        },
        failure(error) => { return 16 }
    }
    let result_option: (Outcome<i32?, i32>) = success(present(19i32))
    match take result_option.transpose() {
        present(success(item)) => { if item != 19 { return 17 } },
        present(failure(error)) => { return 17 },
        none => { return 17 }
    }
    let failed_option: (Outcome<i32, i32>)? = present(failure(20i32))
    match take failed_option.transpose() {
        success(value) => { return 18 },
        failure(error) => { if error != 20 { return 18 } }
    }
    let empty_option: (Outcome<i32, i32>)? = none
    match take empty_option.transpose() {
        success(value) => { if value.is_present() { return 19 } },
        failure(error) => { return 19 }
    }
    let failed_outcome: (Outcome<i32?, i32>) = failure(21i32)
    match take failed_outcome.transpose() {
        present(success(value)) => { return 20 },
        present(failure(error)) => { if error != 21 { return 20 } },
        none => { return 20 }
    }
    0
}
