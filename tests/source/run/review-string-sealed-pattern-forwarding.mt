// profiles: debug release
import alloc.string.String

fn main(): i32 {
    let value = String("(\u{e9})")
    match value.strip_circumfix("(", ")") {
        present(body) => {
            if body != "\u{e9}" { return 1 }
            if body.as_bytes().as_ptr() != unsafe { value.as_ptr().add(1usize) } { return 2 }
        },
        none => { return 3 }
    }
    match value.strip_circumfix('(', ')') {
        present(body) => { if body != "\u{e9}" { return 4 } },
        none => { return 5 }
    }
    let prefixes = ['(', '[']
    let suffixes = [')', ']']
    match value.strip_circumfix(read prefixes, read suffixes) {
        present(body) => { if body != "\u{e9}" { return 6 } },
        none => { return 7 }
    }
    var front_calls = 0
    var back_calls = 0
    match value.strip_circumfix(
        fn(c: char): bool { front_calls += 1; c == '(' },
        fn(c: char): bool { back_calls += 1; c == ')' }
    ) {
        present(body) => { if body != "\u{e9}" { return 8 } },
        none => { return 9 }
    }
    if front_calls != 1 || back_calls != 1 { return 10 }
    let overlap = String("aba")
    if overlap.strip_circumfix("ab", "ba").is_present() { return 11 }
    0
}
