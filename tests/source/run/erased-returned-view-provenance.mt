
copy type Pair { first: i32; second: i32 }
interface Reader { fn pair(): read Pair from self; }
type Holder { value: Pair }
extend Holder implements Reader {
    fn pair(): read Pair from self { read self.value }
}
fn total(read holder: any Reader): i32 {
    let value = holder.pair()
    value.first + value.second
}
fn main() {
    let holder = Holder(Pair(20,22))
    let erased: read any Reader = read holder
    if total(Holder(Pair(20,22))) == 42 && erased.pair().first == 20 { 0 } else { 1 }
}
