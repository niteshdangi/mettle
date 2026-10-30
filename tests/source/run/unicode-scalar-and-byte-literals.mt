
copy type Scalars { character: char; byte: u8 }
fn inspect(character: char, byte: u8) {
    character == '\u{1f642}' && byte == b'\xff'
}
fn main() {
    let value = Scalars('🙂', b'\xff')
    let escaped = '\'' == '\u{27}' && '\\' == '\u{5c}' && '\0' == '\u{0}'
    let character = match value.character { '\0'..='\u{10ffff}' => true }
    let byte = match value.byte { b'\x00'..=b'\xff' => true }
    if inspect(value.character,value.byte) && escaped && character && byte { 0 } else { 1 }
}
