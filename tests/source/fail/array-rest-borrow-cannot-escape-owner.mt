// expect-error: ownership 3:137 live read loan
type Owned { value:i32 }
fn main() { let view: read [Owned;2]; { let values = [Owned(20),Owned(22),Owned(0)]; view = match values { [rest @ ..,_] => read rest } }; view[0].value }
