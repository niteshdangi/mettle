// Same parsing contract as ini_parser, using borrowed text and collection APIs.
import alloc.hash_map.Map
import alloc.string.String
import alloc.vec.List
import core.text.Text

fn parse_number(read text: Text): i64? {
    if text.is_empty() { return none }
    var value = 0i64
    for byte in text.bytes() {
        if byte < b'0' || byte > b'9' { return none }
        value = value * 10 + ((byte - b'0') as i64)
    }
    present(value)
}

fn parse_list(read text: Text, mut out: List<i64>): bool {
    for part in text.split(",") {
        if part.is_empty() { continue }
        let present(value) = parse_number(part) else { return false }
        out.push(value)
    }
    true
}

fn parse(read input: Text, mut map: Map<String, List<i64>>): bool {
    for line in input.split("\n") {
        if line.is_empty() { continue }
        let present((key, rest)) = line.split_once("=") else { return false }
        let values = map.or_insert(String(key), List<i64>())
        if !parse_list(rest, values) { return false }
    }
    true
}

fn sum(read values: List<i64>): i64 {
    var total = 0i64
    for value in values { total += *value }
    total
}

fn main(): i32 {
    var map = Map<String, List<i64>>()
    if !parse("a=1,2,3\nb=40,50\na=4\nc=\n", map) { return 1 }
    if map.len() != 3 { return 2 }
    match map.get("a") {
        present(values) => { if values.len() != 4 || sum(values) != 10 { return 3 } },
        none => { return 4 }
    }
    match map.get("b") {
        present(values) => { if sum(values) != 90 { return 5 } },
        none => { return 6 }
    }
    match map.get("c") {
        present(values) => { if !values.is_empty() { return 7 } },
        none => { return 8 }
    }
    var bad = Map<String, List<i64>>()
    if parse("x=1,zz\n", bad) { return 9 }
    match bad.get("x") {
        present(values) => { if values.len() != 1 || sum(values) != 1 { return 10 } },
        none => { return 11 }
    }
    if !parse("\nempty=,,\nkey=,1,,2,\n=3", map) { return 12 }
    match map.get("key") {
        present(values) => { if values.len() != 2 || sum(values) != 3 { return 13 } },
        none => { return 14 }
    }
    match map.get("") {
        present(values) => { if sum(values) != 3 { return 15 } },
        none => { return 16 }
    }
    if parse("cr=1\r\n", map) { return 17 }
    if parse("extra=1=2", map) { return 18 }
    if parse("missing", map) { return 19 }
    if parse("negative=-1", map) || parse("positive=+1", map) { return 20 }
    match map.get("empty") {
        present(values) => { if !values.is_empty() { return 21 } },
        none => { return 22 }
    }
    0
}
