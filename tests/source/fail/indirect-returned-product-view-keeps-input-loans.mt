// expect-error: ownership 11:5 live read loan

copy type Pair { first: i32; second: i32 }
copy type Reader<region r> { value: read Pair from r }
fn expose(reader: read Reader): read Pair from reader { reader.value }
fn main(): i32 {
    var pair = Pair(20,22)
    let reader = Reader(read pair)
    let pointer: fn(read Reader): read Pair = expose
    let result = pointer(reader)
    pair.first += 1
    result.first + result.second
}
