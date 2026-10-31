import core.float
import core.option
import core.outcome

fn main(): i32 {
    if 1.5f64.algebraic_add(2.25f64) != 3.75f64 { return 1 }
    if 1.5f64.algebraic_sub(2.0f64) != -0.5f64 { return 2 }
    if 1.5f64.algebraic_mul(4.0f64) != 6.0f64 { return 3 }
    if 7.0f64.algebraic_div(2.0f64) != 3.5f64 { return 4 }
    if 7.5f64.algebraic_rem(2.0f64) != 1.5f64 { return 5 }
    if 1.5f32.algebraic_add(2.25f32) != 3.75f32 { return 6 }
    if 1.5f32.algebraic_sub(2.0f32) != -0.5f32 { return 7 }
    if 1.5f32.algebraic_mul(4.0f32) != 6.0f32 { return 8 }
    if 7.0f32.algebraic_div(2.0f32) != 3.5f32 { return 9 }
    if 7.5f32.algebraic_rem(2.0f32) != 1.5f32 { return 10 }
    let nan = 0.0f64.algebraic_div(0.0f64)
    if !nan.is_nan() { return 11 }
    if !1.0f64.algebraic_div(0.0f64).is_infinite() { return 12 }
    if !nan.algebraic_add(1.0f64).is_nan() { return 13 }

    var option_source = 41i32
    match present(mut option_source).copied() {
        present(value) => { if value != 41 { return 20 } },
        none => { return 20 }
    }
    match present(mut option_source).cloned() {
        present(value) => { if value != 41 { return 21 } },
        none => { return 21 }
    }
    var empty_source = 0i32
    let absent: (mut i32 from empty_source)? = none
    if absent.copied().is_present() { return 22 }

    var success_value = 5i32
    var failure_value = 6i32
    let ok_view: ((mut i32 from success_value) throws (mut i32 from success_value)) =
        success(mut success_value)
    match ok_view.copied() {
        success(value) => { if value != 5 { return 30 } },
        failure(_) => { return 30 }
    }
    let err_view: ((mut i32 from failure_value) throws (mut i32 from failure_value)) =
        failure(mut failure_value)
    match err_view.cloned() {
        success(_) => { return 31 },
        failure(error) => { if error != 6 { return 31 } }
    }

    let first: (i32 throws i32) = failure(1i32)
    match first.or(success(9i32)) {
        success(value) => { if value != 9 { return 40 } },
        failure(_) => { return 40 }
    }
    let kept: (i32 throws i32) = success(2i32)
    match kept.or(success(9i32)) {
        success(value) => { if value != 2 { return 41 } },
        failure(_) => { return 41 }
    }
    let retried: (i32 throws i32) = failure(3i32)
    match retried.or(failure(4i32)) {
        success(_) => { return 42 },
        failure(error) => { if error != 4 { return 42 } }
    }
    0
}
