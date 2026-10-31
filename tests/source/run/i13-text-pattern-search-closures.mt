fn main(): i32 {
    let text = "éluna"
    match text.find('a') { present(at) => { if at != 5usize { return 1 } }, none => { return 1 } }
    var forward_calls = 0usize
    {
        var vowel = fn(value: char): bool {
            forward_calls += 1usize
            value == 'u'
        }
        match text.find(mut vowel) {
            present(at) => { if at != 3usize { return 2 } },
            none => { return 2 }
        }
    }
    if forward_calls != 3usize { return 3 }
    var reverse_calls = 0usize
    {
        var vowel = fn(value: char): bool {
            reverse_calls += 1usize
            value == 'a'
        }
        match text.rfind(mut vowel) {
            present(at) => { if at != 5usize { return 4 } },
            none => { return 4 }
        }
    }
    if reverse_calls != 1usize { return 5 }
    if !text.starts_with('é') || !text.ends_with(fn(value: char): bool { value == 'a' }) {
        return 6
    }
    match text.strip_prefix('é') {
        present(rest) => { if rest != "luna" { return 7 } },
        none => { return 7 }
    }
    match text.strip_suffix('a') {
        present(rest) => { if rest != "élun" { return 8 } },
        none => { return 8 }
    }
    match text.find("") { present(at) => { if at != 0usize { return 9 } }, none => { return 9 } }
    match text.rfind("") {
        present(at) => { if at != text.len() { return 10 } },
        none => { return 10 }
    }
    if "!!Hello!!".trim_matches(fn(value: char): bool { value == '!' }) != "Hello" {
        return 11
    }
    0
}
