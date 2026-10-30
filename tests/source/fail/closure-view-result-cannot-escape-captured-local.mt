// expect-error: ownership 7:5 live exclusive loan

fn main(): i32 {
    var f = {
        var l = 1
        fn(): mut i32 { mut l }
    }
    let a = f()
    *a = 1
    0
}
