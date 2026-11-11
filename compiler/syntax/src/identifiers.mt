import alloc.vec.{ List, new }
import mettle_foundation.invalid_utf8
import super.unicode_data.{ XID_START, XID_CONTINUE, COMBINING, DECOMPOSITIONS, DECOMPOSED,
        COMPOSITIONS }

fn contains(read ranges: [u32], scalar: u32): bool {
    var low = 0usize
    var high = ranges.len() / 2usize
    while low < high {
        let middle = low + (high - low) / 2usize
        let index = middle * 2usize
        if scalar < ranges[index] { high = middle }
        else if scalar > ranges[index + 1usize] { low = middle + 1usize }
        else { return true }
    }
    false
}

pub fn is_start(scalar: u32): bool {
    if scalar < 128u32 { return scalar == 95u32 || (scalar >= 65u32 && scalar <= 90u32) ||
            (scalar >= 97u32 && scalar <= 122u32) }
    contains(read XID_START, scalar)
}

pub fn is_continue(scalar: u32): bool {
    if scalar < 128u32 { return is_start(scalar) || (scalar >= 48u32 && scalar <= 57u32) }
    contains(read XID_CONTINUE, scalar)
}

// Source UTF-8 is validated before this decoder is called.
pub(super) fn scalar_at(read bytes: [u8], offset: usize): (u32, usize) {
    let first = bytes[offset]
    let width = if first < 128u8 { 1usize } else if first < 0xe0u8 { 2usize } else if first <
        0xf0u8 { 3usize } else { 4usize }
    var scalar = if width == 1 { first as u32 } else { (first & (0x7fu8 >> width)) as u32 }
    var index = 1usize
    while index < width { scalar = (scalar << 6u32) | (bytes[offset + index] &
        0x3fu8) as u32; index += 1usize }
    (scalar, width)
}

fn combining_class(scalar: u32): usize {
    let table: read [u32] = read COMBINING
    var low = 0usize
    var high = table.len() / 3usize
    while low < high {
        let middle = low + (high - low) / 2usize
        let index = middle * 3usize
        if scalar < table[index] { high = middle }
        else if scalar > table[index + 1usize] { low = middle + 1usize }
        else { return table[index + 2usize] as usize }
    }
    0usize
}

fn decompose(scalar: u32, mut out: List<u32>): Unit {
    if scalar >= 0xac00u32 && scalar < 0xd7a4u32 {
        let index = scalar - 0xac00u32
        out.push(0x1100u32 + index / 588u32)
        out.push(0x1161u32 + (index % 588u32) / 28u32)
        let trailing = index % 28u32
        if trailing != 0u32 { out.push(0x11a7u32 + trailing) }
        return
    }
    let table: read [u32] = read DECOMPOSITIONS
    var low = 0usize
    var high = table.len() / 3usize
    while low < high {
        let middle = low + (high - low) / 2usize
        let index = middle * 3usize
        if scalar < table[index] { high = middle }
        else if scalar > table[index] { low = middle + 1usize }
        else {
            let begin = table[index + 1usize] as usize
            let end = begin + table[index + 2usize] as usize
            var at = begin
            while at < end { let value = DECOMPOSED[at]; out.push(value); at += 1usize }
            return
        }
    }
    out.push(scalar)
}

fn reorder(mut scalars: List<u32>): Unit {
    var scratch = new<u32>()
    var begin = 0usize
    while begin < scalars.len() {
        if combining_class(scalars[begin]) == 0usize { begin += 1usize; continue }
        var end = begin
        var previous = 0usize
        var unordered = false
        while end < scalars.len() {
            let category = combining_class(scalars[end])
            if category == 0usize { break }
            if category < previous { unordered = true }
            previous = category
            end += 1usize
        }
        if unordered {
            var counts = [0usize; 256]
            scratch.clear()
            var index = begin
            while index <
                end { counts[combining_class(scalars[index])] += 1usize; scratch.push(0u32); index += 1usize }
            var offset = 0usize
            var category = 0usize
            while category < 256usize {
                let count = counts[category]
                counts[category] = offset
                offset += count
                category += 1usize
            }
            index = begin
            while index < end {
                let category = combining_class(scalars[index])
                scratch[counts[category]] = scalars[index]
                counts[category] += 1usize
                index += 1usize
            }
            index = begin
            while index < end { scalars[index] = scratch[index - begin]; index += 1usize }
        }
        begin = end
    }
}

fn composition(first: u32, second: u32): u32? {
    if first >= 0x1100u32 && first < 0x1113u32 && second >= 0x1161u32 && second < 0x1176u32 {
        return present(0xac00u32 + (first - 0x1100u32) * 588u32 + (second - 0x1161u32) * 28u32)
    }
    if first >= 0xac00u32 && first < 0xd7a4u32 && (first - 0xac00u32) % 28u32 == 0u32 && second >
        0x11a7u32 && second < 0x11c3u32 {
        return present(first + second - 0x11a7u32)
    }
    let table: read [u32] = read COMPOSITIONS
    var low = 0usize
    var high = table.len() / 3usize
    while low < high {
        let middle = low + (high - low) / 2usize
        let index = middle * 3usize
        let left = table[index]
        let right = table[index + 1usize]
        if first < left || (first == left && second < right) { high = middle }
        else if first > left || second > right { low = middle + 1usize }
        else { return present(table[index + 2usize]) }
    }
    none
}

fn compose(mut scalars: List<u32>): Unit {
    var starter: usize? = none
    var previous = 0usize
    var read_at = 0usize
    var write_at = 0usize
    while read_at < scalars.len() {
        let scalar = scalars[read_at]
        let category = combining_class(scalar)
        read_at += 1usize
        if let present(index) = starter {
            if previous == 0usize || previous < category {
                if let present(combined) = composition(scalars[index],
                    scalar) { scalars[index] = combined; continue }
            }
        }
        scalars[write_at] = scalar
        if category == 0usize { starter = present(write_at) }
        previous = category
        write_at += 1usize
    }
    scalars.truncate(write_at)
}

fn encode(scalar: u32, mut bytes: List<u8>): Unit {
    if scalar < 128u32 { bytes.push(scalar as u8) }
    else {
        if scalar < 0x800u32 { bytes.push((0xc0u32 | (scalar >> 6u32)) as u8) }
        else {
            if scalar < 0x10000u32 { bytes.push((0xe0u32 | (scalar >> 12u32)) as u8) }
            else { bytes.push((0xf0u32 | (scalar >> 18u32)) as u8); bytes.push((0x80u32 |
                ((scalar >> 12u32) & 0x3fu32)) as u8) }
            bytes.push((0x80u32 | ((scalar >> 6u32) & 0x3fu32)) as u8)
        }
        bytes.push((0x80u32 | (scalar & 0x3fu32)) as u8)
    }
}

pub fn nfc(read bytes: [u8]): List<u8>? {
    if invalid_utf8(bytes).is_present() { return none }
    var out = new<u8>()
    if bytes.is_ascii() { out.extend_from_slice(bytes); return present(out) }
    var scalars = new<u32>()
    var offset = 0usize
    while offset < bytes.len() {
        let decoded = scalar_at(bytes, offset)
        decompose(decoded.0, mut scalars)
        offset += decoded.1
    }
    reorder(mut scalars)
    compose(mut scalars)
    for scalar in scalars.as_slice() { encode(scalar, mut out) }
    present(out)
}
