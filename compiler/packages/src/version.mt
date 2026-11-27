import alloc.string.{ String, from_text }
import core.iter.Iterator
import core.text.Text
import super.data.alpha

pub copy type Core { major: u64; minor: u64; patch: u64 }
pub type Version { core: Core; pre: String }
type Partial { version: Version; components: usize; wildcard: bool }

fn digit(c: u8): bool { c >= b'0' && c <= b'9' }

fn numeric(read text: Text): bool {
    if text.is_empty() { return false }
    for byte in text.as_bytes() { if !digit(byte) { return false } }
    true
}

fn identifiers(read text: Text, prerelease: bool): bool {
    for part in text.split('.') {
        if part.is_empty() { return false }
        for byte in part.as_bytes() { if !digit(byte) && !alpha(byte) && byte != b'-' { return false } }
        if prerelease && part.len() > 1 && part.as_bytes()[0] == b'0' && numeric(part) { return false }
    }
    true
}

fn partial(read text: Text, complete: bool): Partial? {
    let plus = text.find_byte(b'+').or(text.len())
    let (base, build) = text.split_at(plus)
    if complete && plus < text.len() && !identifiers(build.split_at(1usize).1, false) { return none }
    let dash = base.find_byte(b'-').or(base.len())
    let (numbers, _) = base.split_at(dash)
    let (_, pre) = base.split_at(if dash < base.len() { dash + 1 } else { dash })
    if dash < base.len() && !identifiers(pre, true) { return none }
    var components = [0u64; 3]
    var count = 0usize
    var wildcard = false
    for part in numbers.split('.') {
        if count == 3 || wildcard { return none }
        if part == "*" || part == "x" || part == "X" {
            if complete { return none }
            wildcard = true
            continue
        }
        if !numeric(part) || part.len() > 19 || (part.len() > 1 && part.as_bytes()[0] == b'0') { return none }
        var value = 0u64
        for byte in part.as_bytes() { value = value * 10 + (byte - b'0') as u64 }
        components[count] = value
        count += 1
    }
    if complete && count != 3 { return none }
    if !pre.is_empty() && count + (if wildcard { 1 } else { 0 }) != 3 { return none }
    present(Partial(Version(Core(components[0], components[1], components[2]), from_text(pre)), count, wildcard))
}

pub fn parse(read text: Text): Version? {
    let present(parsed) = partial(text, true) else { return none }
    present(take parsed.version)
}

fn compare_core(a: Core, b: Core): i32 {
    if a.major != b.major { return if a.major < b.major { -1 } else { 1 } }
    if a.minor != b.minor { return if a.minor < b.minor { -1 } else { 1 } }
    if a.patch != b.patch { return if a.patch < b.patch { -1 } else { 1 } }
    0
}

pub fn compare(read a: Version, read b: Version): i32 {
    let order = compare_core(a.core, b.core)
    if order != 0 { return order }
    let left = a.pre.as_text()
    let right = b.pre.as_text()
    if left.is_empty() { return if right.is_empty() { 0 } else { 1 } }
    if right.is_empty() { return -1 }
    var x = left.split('.')
    var y = right.split('.')
    loop {
        let first = x.next()
        let second = y.next()
        let present(p) = first else { return if second.is_present() { -1 } else { 0 } }
        let present(q) = second else { return 1 }
        if p == q { continue }
        let pn = numeric(p)
        let qn = numeric(q)
        if pn != qn { return if pn { -1 } else { 1 } }
        if pn && p.len() != q.len() { return if p.len() < q.len() { -1 } else { 1 } }
        return if p < q { -1 } else { 1 }
    }
}

fn before_release(read version: Version, core: Core): bool {
    let order = compare_core(version.core, core)
    order < 0 || (order == 0 && !version.pre.is_empty())
}

fn next_prefix(core: Core, components: usize): Core {
    if components <= 1 { Core(core.major + 1, 0, 0) }
    else { Core(core.major, core.minor + 1, 0) }
}

pub fn matches(read requirement: Text, read candidate: Version): bool? {
    var accepted = true
    var prerelease = candidate.pre.is_empty()
    for term in requirement.split(',') {
        let trimmed = term.trim_matches(' ')
        let op = if trimmed.starts_with(">=") { ">=" } else if trimmed.starts_with("<=") { "<=" }
            else if trimmed.starts_with(">") { ">" } else if trimmed.starts_with("<") { "<" }
            else if trimmed.starts_with("=") { "=" } else if trimmed.starts_with("^") { "^" }
            else if trimmed.starts_with("~") { "~" } else { "" }
        let rest = trimmed.split_at(op.len()).1.trim_matches(' ')
        let present(p) = partial(rest, false) else { return none }
        let core = p.version.core
        let count = p.components
        let order = compare(candidate, p.version)
        let before = before_release(candidate, next_prefix(core, count))
        if !p.version.pre.is_empty() && compare_core(candidate.core, core) == 0 { prerelease = true }
        if count == 0 && (op == "<" || op == ">" || op == "<=") { return none }
        let holds = if op == ">=" { order >= 0 }
            else if op == ">" { if count == 3 { order > 0 } else { !before } }
            else if op == "<" { order < 0 }
            else if op == "<=" { if count == 3 { order <= 0 } else { before } }
            else if op == "=" || op == "~" {
                if op == "=" && count == 3 { order == 0 } else { order >= 0 && (count == 0 || before) }
            } else {
                let upper = if (op == "" && p.wildcard) || core.major != 0 || count == 1 {
                    next_prefix(core, if op == "" && p.wildcard { count } else { 1 })
                } else if core.minor != 0 || count == 2 {
                    next_prefix(core, 2)
                } else { Core(0, 0, core.patch + 1) }
                order >= 0 && (count == 0 || before_release(candidate, upper))
            }
        accepted = accepted && holds
    }
    present(accepted && prerelease)
}

@test
fn requirement_boundaries(): Unit {
    let release = parse("0.1.4+metadata").or_panic()
    let next = parse("0.2.0").or_panic()
    let prerelease = parse("0.2.0-rc.10").or_panic()
    assert(matches("^0.1, >=0.1.4", release) == present(true), "compatible release was rejected")
    assert(matches("^0.1", next) == present(false), "incompatible minor release was accepted")
    assert(matches(">=0.1", prerelease) == present(false), "unrequested prerelease was accepted")
    assert(matches(">=0.2.0-rc.2, <0.2.0", prerelease) == present(true), "numeric prerelease order is incorrect")
    assert(matches("*,", release).is_none(), "empty comparator was accepted")
}
