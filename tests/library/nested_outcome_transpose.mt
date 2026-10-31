import core.option
import core.outcome

fn main(): i32 {
    let nested: ((i32 throws i32) throws i32) = success(success(31))
    match take nested {
        success(inner) => match take inner {
            success(value) => { if value != 31 { return 1 } },
            failure(_) => { return 2 }
        },
        failure(_) => { return 3 }
    }
    let nested_inner_failure: ((i32 throws i32) throws i32) =
        success(failure(5))
    match take nested_inner_failure {
        success(inner) => match take inner {
            success(_) => { return 15 },
            failure(error) => { if error != 5 { return 16 } }
        },
        failure(_) => { return 17 }
    }
    let nested_outer_failure: ((i32 throws i32) throws i32) =
        failure(9)
    match take nested_outer_failure {
        success(_) => { return 18 },
        failure(error) => { if error != 9 { return 19 } }
    }

    let maybe_result: (i32 throws i32)? = present(success(41))
    let transposed = maybe_result.transpose()
    match take transposed {
        success(value) => match take value {
            present(number) => { if number != 41 { return 4 } },
            none => { return 5 }
        },
        failure(_) => { return 6 }
    }

    let failed_result: (i32 throws i32)? = present(failure(7))
    let failed_transposed = failed_result.transpose()
    match take failed_transposed {
        success(_) => { return 7 },
        failure(error) => { if error != 7 { return 8 } }
    }

    let absent_result: (i32 throws i32)? = none
    let absent_transposed = absent_result.transpose()
    match take absent_transposed {
        success(value) => { if value.is_present() { return 9 } },
        failure(_) => { return 10 }
    }

    let success_without_value: (i32? throws i32) = success(none)
    if success_without_value.transpose().is_present() { return 11 }
    let success_with_value: (i32? throws i32) = success(present(51))
    let success_transposed = success_with_value.transpose()
    match take success_transposed {
        present(result) => match take result {
            success(value) => { if value != 51 { return 20 } },
            failure(_) => { return 21 }
        },
        none => { return 22 }
    }
    let failure_without_value: (i32? throws i32) = failure(13)
    let failure_transposed = failure_without_value.transpose()
    match take failure_transposed {
        present(result) => match take result {
            success(_) => { return 12 },
            failure(error) => { if error != 13 { return 13 } }
        },
        none => { return 14 }
    }
    0
}
