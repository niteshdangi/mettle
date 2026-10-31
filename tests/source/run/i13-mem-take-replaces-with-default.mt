// core.mem.`take` leaves the default value behind and returns the old value.
type Counted { value: i32 }
extend Counted implements core.default.Default {
    static fn default(): Counted { Counted(-1) }
}
fn main(): i32 {
    var number = 5
    let old = core.mem.`take`(number)
    if old != 5 || number != 0 { return 1 }
    var flag = true
    let was = core.mem.`take`(flag)
    if !was || flag { return 2 }
    var maybe: i32? = present(9)
    let kept = core.mem.`take`(maybe)
    match kept { present(v) => { if v != 9 { return 3 } }, none => { return 4 } }
    match maybe { present(v) => { return 5 }, none => {} }
    var item = Counted(7)
    let previous = core.mem.`take`(item)
    if previous.value != 7 || item.value != -1 { return 6 }
    0
}
