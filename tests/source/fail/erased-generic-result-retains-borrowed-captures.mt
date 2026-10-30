// expect-error: ownership 14:5 live read loan

copy type Pair { first: i32; second: i32 }
interface Readable<T: Copy> { fn value(): T; }
copy type Reader<region r> { value: read Pair from r }
extend<region r> Reader<region r> implements Readable<read Pair from r> {
    fn value(): read Pair from r { self.value }
}
fn main() {
    var original = Pair(20,22)
    let reader = Reader(read original)
    let erased: read any Readable<read Pair> = read reader
    let result = erased.value()
    original.first += 1
    result.first + result.second
}
