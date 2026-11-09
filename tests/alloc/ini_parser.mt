// Structured parser plus collection workload, built without std:
// `name=1,2,3` lines accumulate into a Map<String, List<i64>>.
import alloc.hash_map.Map
import alloc.string.String
import alloc.vec.List
import package.core.text.Text

fn parse_number(read t: Text): i64? {
    let bytes = t.as_bytes()
    if bytes.len() == 0usize { return none }
    var value = 0i64
    var i = 0usize
    while i < bytes.len() {
        let b = bytes[i]
        if b < 0x30u8 || b > 0x39u8 { return none }
        value = value * 10i64 + ((b - 0x30u8) as i64)
        i += 1usize
    }
    present(value)
}

// Adds every comma-separated number in `list` to `out`; false on malformed input.
fn parse_list(read list: Text, mut out: List<i64>): bool {
    var start = 0usize
    var i = 0usize
    let bytes = list.as_bytes()
    while i <= bytes.len() {
        if i == bytes.len() || bytes[i] == 0x2cu8 {
            if i > start {
                match list.get(start, i) {
                    present(part) => match parse_number(part) {
                        present(n) => { out.push(n) },
                        none => { return false }
                    },
                    none => { return false }
                }
            }
            start = i + 1usize
        }
        i += 1usize
    }
    true
}

fn parse(read input: Text, mut map: Map<String, List<i64>>): bool {
    var line_start = 0usize
    var i = 0usize
    let bytes = input.as_bytes()
    while i <= bytes.len() {
        if i == bytes.len() || bytes[i] == 0x0au8 {
            if i > line_start {
                let line = match input.get(line_start, i) { present(l) => l, none => { return false } }
                let eq = match line.find_byte(0x3du8) { present(e) => e, none => { return false } }
                let key = match line.get(0usize, eq) { present(k) => k, none => { return false } }
                let rest = match line.get(eq + 1usize, line.len()) { present(r) => r, none => { return false } }
                let list = map.or_insert(alloc.string.from_text(key), alloc.vec.new<i64>())
                if !parse_list(rest, list) { return false }
            }
            line_start = i + 1usize
        }
        i += 1usize
    }
    true
}

fn sum(read v: List<i64>): i64 {
    var total = 0i64
    var i = 0usize
    while i < v.len() {
        total += v[i]
        i += 1usize
    }
    total
}

fn main(): i32 {
    var map = alloc.hash_map.new<String, List<i64>>()
    if !parse("a=1,2,3\nb=40,50\na=4\nc=\n", mut map) { return 1 }
    if map.len() != 3usize { return 2 }
    match map.get(alloc.string.from_text("a")) {
        present(v) => { if v.len() != 4usize || sum(v) != 10i64 { return 3 } },
        none => { return 4 }
    }
    match map.get(alloc.string.from_text("b")) {
        present(v) => { if sum(v) != 90i64 { return 5 } },
        none => { return 6 }
    }
    match map.get(alloc.string.from_text("c")) {
        present(v) => { if !v.is_empty() { return 7 } },
        none => { return 8 }
    }
    var bad = alloc.hash_map.new<String, List<i64>>()
    if parse("x=1,zz\n", mut bad) { return 9 }
    0
}
