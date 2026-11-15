import super.clone.Clone
import super.fmt.{Debug, Display, Error, Formatter, Write}
import super.iter.{BidirectionalIterator, ExactSizeIterator, FusedIterator, Iterator}
import super.num

pub copy type EscapeDefault { bytes: [u8; 4]; front: usize; back: usize }

pub fn escape_default(value: u8): EscapeDefault {
    var source = value.escape_ascii()
    var bytes = [0u8; 4]
    var back = 0usize
    while back < 4usize {
        match source.next() {
            present(byte) => {
                bytes[back] = byte
                back += 1usize
            },
            none => { break }
        }
    }
    EscapeDefault(bytes, 0usize, back)
}

extend EscapeDefault implements Clone {
    fn clone(): EscapeDefault { EscapeDefault(self.bytes, self.front, self.back) }
}

extend EscapeDefault implements Iterator {
    type Item = u8
    fn size_hint(): (usize, usize?) {
        let remaining = self.back - self.front
        (remaining, present(remaining))
    }
    mut fn next(): u8? {
        if self.front == self.back { return none }
        let value = self.bytes[self.front]
        self.front += 1usize
        present(value)
    }
}

extend EscapeDefault implements BidirectionalIterator {
    mut fn next_back(): u8? {
        if self.front == self.back { return none }
        self.back -= 1usize
        present(self.bytes[self.back])
    }
}
extend EscapeDefault implements ExactSizeIterator {}
extend EscapeDefault implements FusedIterator {}

extend EscapeDefault implements Display {
    fn fmt(mut f: Formatter): Unit throws Error {
        var index = self.front
        while index < self.back {
            try f.write_char(self.bytes[index] as char)
            index += 1usize
        }
    }
}
extend EscapeDefault implements Debug {
    fn fmt(mut f: Formatter): Unit throws Error {
        try f.write_str("EscapeDefault { .. }")
    }
}
