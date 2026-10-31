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
    type Target = i32
    mut fn deref_mut(): mut i32 from self { mut self.value }
}

fn expect_15(value: read i32): Unit {
    if *value != 15 { core.panic.panic("inspect did not receive the success value") }
}

fn borrowed_success<region r>(
    value: read i32 from r
): ((read i32 from r) throws (read i32 from r)) {
    success(read value)
}

fn borrowed_failure<region r>(
    value: read i32 from r
): ((read i32 from r) throws (read i32 from r)) {
    failure(read value)
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
    let wrapped_outcome: (Wrapped throws i32) = success(Wrapped(7))
    match wrapped_outcome.as_deref() {
        success(value) => { if *value != 7 { return 5 } },
        failure(_) => { return 5 }
    }
    var mutable_wrapped: Wrapped? = present(Wrapped(6))
    match mutable_wrapped.as_deref_mut() {
        present(value) => { *value += 1 },
        none => { return 6 }
    }
    match mutable_wrapped {
        present(value) => { if value.value != 7 { return 7 } },
        none => { return 7 }
    }
    var mutable_wrapped_outcome: (Wrapped throws i32) = success(Wrapped(8))
    match mutable_wrapped_outcome.as_deref_mut() {
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
    match selected.take_if(fn(value: mut i32): bool { *value > 8 }) {
        present(value) => { if value != 9 { return 14 } },
        none => { return 14 }
    }
    if selected.is_present() { return 15 }
    let unchecked = unsafe { present(11i32).unwrap_unchecked() }
    if unchecked != 11 { return 16 }

    let outcome: (i32 throws i32) = success(12)
    match outcome.as_ref() {
        success(value) => { if *value != 12 { return 17 } },
        failure(_) => { return 17 }
    }
    let flattened: (i32 throws i32) = success(success(13i32)).flatten()
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
    var mutable_outcome: (i32 throws i32) = success(19)
    match mutable_outcome.as_mut() {
        success(value) => { *value += 1 },
        failure(_) => { return 21 }
    }
    match mutable_outcome {
        success(value) => { if value != 20 { return 22 } },
        failure(_) => { return 22 }
    }
    if !success(13i32).is_ok_and(fn(value: take i32): bool { value == 13 }) {
        return 23
    }
    if !failure(14i32).is_err_and(fn(error: take i32): bool { error == 14 }) {
        return 24
    }
    match success(15i32).inspect(expect_15) {
        success(value) => { if value != 15 { return 25 } },
        failure(_) => { return 25 }
    }
    if failure(16i32).unwrap_err() != 16 { return 26 }
    if failure(17i32).expect_err("expected failure") != 17 { return 27 }
    let unchecked_error = unsafe { failure(18i32).unwrap_err_unchecked() }
    if unchecked_error != 18 { return 28 }
    0
}
