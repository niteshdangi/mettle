
copy type Ref<region r> { value: read i32 from r }
fn shorten<region a, region b>(
    take value: Ref<region a>
): Ref<region b> where region a: b { take value }
fn reborrow<region a, region b>(
    take value: (mut i32 from a)
): mut i32 from b where region a: b { take value }
fn main() {
    var value = 1
    let pointer = reborrow(mut value)
    *pointer = 42
    let wrapper = shorten(Ref(read value))
    if *wrapper.value == 42 { 0 } else { 1 }
}
