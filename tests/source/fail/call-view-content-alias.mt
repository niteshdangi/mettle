// expect-error: ownership 4:60 live read loan
copy type R<region r> { value: read i32 from r }
fn both(reader: read R, writer: mut i32) { writer = *reader.value }
fn main() { var x = 1; let reader = R(read x); both(reader,x); 0 }
