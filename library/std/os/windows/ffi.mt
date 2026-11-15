import alloc.vec
import core.clone.Clone
import core.iter.Iterator
import core.slice
import std.ffi as os
import std.ffi.{OsStr, OsString}

pub interface OsStrExt {
    fn encode_wide<region r>(
        receiver read self: OsStr from r
    ): EncodeWide<r>;
}

pub interface OsStringExt: Sized {
    static fn from_wide(read wide: [u16]): Self;
}

pub type EncodeWide<region r> {
    value: read OsStr from r
    index: usize
    pending: u16?
}

fn encode_wide<region r>(read value: OsStr from r): EncodeWide<r> {
    EncodeWide(value, 0usize, none)
}

extend<region r> OsStr implements OsStrExt {
    fn encode_wide<region s>(
        receiver read self: OsStr from s
    ): EncodeWide<s> {
        encode_wide(self)
    }
}

extend OsString implements OsStringExt {
    static fn from_wide(read wide: [u16]): OsString {
        var bytes = vec.new<u8>()
        var index = 0usize
        while index < wide.len() {
            let first = wide[index] as u32
            var scalar = first
            if first >= 0xd800u32 && first <= 0xdbffu32 &&
                index + 1usize < wide.len() {
                let second = wide[index + 1usize] as u32
                if second >= 0xdc00u32 && second <= 0xdfffu32 {
                    scalar = 0x10000u32 + ((first - 0xd800u32) << 10u32) +
                        (second - 0xdc00u32)
                    index += 1usize
                }
            }
            var encoded: [u8; 4] = [0u8, 0u8, 0u8, 0u8]
            let width = os.encode_wtf8_scalar(scalar, mut encoded)
            bytes.extend_from_slice(
                slice.subslice(encoded.as_slice(), 0usize, width).or_panic()
            )
            index += 1usize
        }
        os.os_string_from_vec(bytes)
    }
}

extend<region r> EncodeWide<region r> implements Iterator {
    type Item = u16

    mut fn next(): u16? {
        match take self.pending {
            present(unit) => { return present(unit) },
            none => {}
        }
        let bytes = self.value.as_bytes()
        if self.index >= bytes.len() { return none }
        let (scalar, next_index) = os.decode_wtf8(bytes, self.index)
        self.index = next_index
        if scalar > 0xffffu32 {
            let supplementary = scalar - 0x10000u32
            self.pending = present((0xdc00u32 + (supplementary & 0x3ffu32)) as u16)
            return present((0xd800u32 + (supplementary >> 10u32)) as u16)
        }
        present(scalar as u16)
    }
}

extend<region r> EncodeWide<region r> implements Clone {
    fn clone(): EncodeWide<region r> {
        EncodeWide(self.value, self.index, self.pending)
    }
}
