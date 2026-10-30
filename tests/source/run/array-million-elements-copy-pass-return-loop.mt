
static TABLE: [u8; 1_000_000] = [5; 1_000_000];
static ZEROS: [i32; 300_000] = [0; 300_000];
fn sum(v: read [u8; 1_000_000]): i32 {
    var total = 0
    for x in read v { total += x as i32 }
    total
}
fn byvalue(v: take [u8; 1_000_000]): i32 {
    var total = 0
    for x in take v { total += x as i32 }
    total
}
fn make(): [u8; 1_000_000] { [3; 1_000_000] }
fn bump(v: mut [u8; 1_000_000]) { for x in mut v { x += 1 } }
fn main(): i32 {
    var a = make()
    var b = a
    b[10] = 9
    if a[10] != 3 { return 1 }
    if b[10] != 9 { return 2 }
    bump(mut a)
    if a[999_999] != 4 { return 3 }
    if sum(a) != 4_000_000 { return 4 }
    var c = b
    if byvalue(c) != 3_000_000 + 6 { return 5 }
    if TABLE[999_999] != 5 || ZEROS[299_999] != 0 { return 6 }
    var i = 0
    while i < 1_000_000 { b[i] = (i % 251) as u8; i += 1 }
    if b[250] != 250 || b[251] != 0 { return 7 }
    var same = true
    i = 0
    while i < 1_000_000 { if a[i] != 4 { same = false }; i += 1 }
    if !same { return 8 }
    0
}
