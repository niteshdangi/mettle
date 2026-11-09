
copy type Pair { first: i32; second: i32 }
copy type Reader<region r> { value: read Pair from r }
type Writer<region source, region storage> {
    value: mut Reader<region source> from storage
}
fn expose<region source, region storage>(
    mut writer: Writer<region source,region storage>): mut Reader<region source> from writer {
    mut *writer.value
}
fn main(): i32 {
    let original = Pair(0,0)
    let replacement = Pair(20,22)
    var reader = Reader(read original)
    var writer = Writer(mut reader)
    let pointer: for<region source,region storage> fn(mut Writer<region source,region storage>): mut Reader<region source> = expose
    let result = pointer(writer)
    result.value = read replacement
    if result.value.first + result.value.second == 42 { 0 } else { 1 }
}
