import core.default.Default
import core.option
import core.outcome
import core.ops.Deref
import core.ops.DerefMut

type Wrapped { value: i32 }
extend Wrapped implements Deref {
    type Target = i32
    fn deref(): read i32 from self { read self.value }
}
extend Wrapped implements DerefMut {
    mut fn deref_mut(): mut i32 from self { mut self.value }
}

fn borrowed_success<region r>(
    read value: i32 from r
): (Outcome<(read i32 from r), i32>) {
    success(read value)
}

// Only the success value is borrowed; the failure is an owned value.
fn borrowed_failure<region r>(
    read value: i32 from r
): (Outcome<(read i32 from r), i32>) {
    failure(7)
}

fn main(): i32 {
    let source = 7i32
    match present(source).as_ref() {
        present(value) => { if *value != 7 { return 1 } },
        none => { return 1 }
    }
    let copied = present(read source).copied()
    match copied {
        present(value) => { if value != 7 { return 2 } },
        none => { return 2 }
    }
    let cloned = present(read source).cloned()
    match cloned {
        present(value) => { if value != 7 { return 3 } },
        none => { return 3 }
    }
    let wrapped: Wrapped? = present(Wrapped(6))
    match wrapped.as_deref() {
        present(value) => { if *value != 6 { return 4 } },
        none => { return 4 }
    }
    let wrapped_outcome: (Outcome<Wrapped, i32>) = success(Wrapped(7))
    match wrapped_outcome.as_deref() {
        success(value) => { if *value != 7 { return 5 } },
        failure(_) => { return 5 }
    }
    var mutable_wrapped: Wrapped? = present(Wrapped(6))
    match take mutable_wrapped.as_deref_mut() {
        present(value) => { *value += 1 },
        none => { return 6 }
    }
    match mutable_wrapped {
        present(value) => { if value.value != 7 { return 7 } },
        none => { return 7 }
    }
    var mutable_wrapped_outcome: (Outcome<Wrapped, i32>) = success(Wrapped(8))
    match take mutable_wrapped_outcome.as_deref_mut() {
        success(value) => { *value += 1 },
        failure(_) => { return 8 }
    }
    match mutable_wrapped_outcome {
        success(value) => { if value.value != 9 { return 9 } },
        failure(_) => { return 9 }
    }

    var maybe: i32? = none
    *maybe.get_or_insert(3) += 2
    match maybe {
        present(value) => { if value != 5 { return 10 } },
        none => { return 10 }
    }
    var made: i32? = none
    if *made.get_or_insert_with(fn(): i32 { 8 }) != 8 { return 11 }
    let previous = maybe.`take`()
    match previous {
        present(value) => { if value != 5 { return 12 } },
        none => { return 12 }
    }
    let inserted = maybe.get_or_insert_default()
    if *inserted != 0 { return 13 }

    var selected: i32? = present(9)
    match selected.take_if(take fn(mut value: i32): bool { value > 8 }) {
        present(value) => { if value != 9 { return 14 } },
        none => { return 14 }
    }
    if selected.is_present() { return 15 }
    let unchecked = unsafe { present(11i32).unwrap_unchecked() }
    if unchecked != 11 { return 16 }

    let outcome: (Outcome<i32, i32>) = success(12)
    match outcome.as_ref() {
        success(value) => { if *value != 12 { return 17 } },
        failure(_) => { return 17 }
    }
    let nested: (Outcome<(Outcome<i32, i32>), i32>) = success(success(13i32))
    let flattened: (Outcome<i32, i32>) = nested.flatten()
    if flattened.unwrap() != 13 { return 18 }
    let copied_outcome = borrowed_success(read source).copied()
    match copied_outcome {
        success(value) => { if value != 7 { return 19 } },
        failure(_) => { return 19 }
    }
    let cloned_outcome = borrowed_failure(read source).cloned()
    match cloned_outcome {
        success(_) => { return 20 },
        failure(error) => { if error != 7 { return 20 } }
    }
    var mutable_outcome: (Outcome<i32, i32>) = success(19)
    match take mutable_outcome.as_mut() {
        success(value) => { *value += 1 },
        failure(_) => { return 21 }
    }
    match mutable_outcome {
        success(value) => { if value != 20 { return 22 } },
        failure(_) => { return 22 }
    }
    let checked_success: (Outcome<i32, i32>) = success(13i32)
    if !checked_success.is_ok_and(fn(take value: i32): bool { value == 13 }) {
        return 23
    }
    let checked_failure: (Outcome<i32, i32>) = failure(14i32)
    if !checked_failure.is_err_and(fn(take error: i32): bool { error == 14 }) {
        return 24
    }
    let inspected_success: (Outcome<i32, i32>) = success(15i32)
    var inspect_calls = 0
    match inspected_success.inspect(fn(read value: i32): Unit {
        inspect_calls += 1
        if value != 15 { core.panic.panic("inspect did not receive the success value") }
    }) {
        success(value) => { if value != 15 { return 25 } },
        failure(_) => { return 25 }
    }
    if inspect_calls != 1 { return 29 }
    let unwrapped_failure: (Outcome<i32, i32>) = failure(16i32)
    if unwrapped_failure.unwrap_err() != 16 { return 26 }
    let expected_failure: (Outcome<i32, i32>) = failure(17i32)
    if expected_failure.expect_err("expected failure") != 17 { return 27 }
    let unchecked_failure: (Outcome<i32, i32>) = failure(18i32)
    let unchecked_error = unsafe { unchecked_failure.unwrap_err_unchecked() }
    if unchecked_error != 18 { return 28 }
    0
}
