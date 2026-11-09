
copy type Pair { first: i32; second: i32 }
copy type Reader<region r> { value: read Pair from r }
fn whole(read reader: Reader): read Pair from reader { reader.value }
fn field(read reader: Reader): read i32 from reader { read reader.value.second }
fn main() {
    var pair = Pair(20, 22)
    let reader = Reader(read pair)
    let observed = whole(reader).first + *field(reader)
    pair.second = 0
    if observed == 42 && pair.second == 0 { 0 } else { 1 }
}
