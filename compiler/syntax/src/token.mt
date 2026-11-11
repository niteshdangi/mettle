import mettle_foundation.Span
import alloc.vec.List
import super.identifiers.nfc

pub copy enum Kind {
    Word, Integer, Symbol, Space, Comment, Newline, End, Character, Byte,
        Floating, QuotedWord, Text, PrefixedText, FormatOpen, FormatPiece,
        FormatHoleOpen, FormatHoleClose, FormatClose
}

pub copy type Token { pub kind: Kind; pub span: Span }

extend Token {
    pub fn identifier(read source: [u8]): List<u8>? {
        if !(self.kind.is(Kind.Word) || self.kind.is(Kind.QuotedWord)) || self.span.begin > self.span.end || self.span.end as usize > source.len() { return none }
        var begin = self.span.begin as usize
        var end = self.span.end as usize
        if self.kind.is(Kind.QuotedWord) {
            if end - begin < 2usize || source[begin] != b'`' || source[end - 1usize] != b'`' { return none }
            begin += 1usize
            end -= 1usize
        }
        nfc(read source[begin..end])
    }
}

extend Kind {
    pub fn is(other: Kind): bool { (self as u32) == (other as u32) }
}

pub fn reference_kind(kind: Kind): u32 {
    match kind {
        Kind.Word => 0, Kind.Integer => 1, Kind.Symbol => 2, Kind.Space => 3,
        Kind.Comment => 4, Kind.Newline => 5, Kind.End => 6, Kind.Character => 7,
        Kind.Byte => 8, Kind.Floating => 9, Kind.QuotedWord => 10, Kind.Text => 11,
        Kind.PrefixedText => 12, Kind.FormatOpen => 13, Kind.FormatPiece => 14,
        Kind.FormatHoleOpen => 15, Kind.FormatHoleClose => 16, Kind.FormatClose => 17
    }
}
