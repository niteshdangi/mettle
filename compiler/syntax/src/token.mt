import mettle_foundation.Span

pub copy enum Kind {
    Word, Integer, Symbol, Space, Comment, Newline, End, Character, Byte,
        Floating, QuotedWord, Text, PrefixedText, FormatOpen, FormatPiece,
        FormatHoleOpen, FormatHoleClose, FormatClose
}

pub copy type Token { pub kind: Kind; pub span: Span }

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
