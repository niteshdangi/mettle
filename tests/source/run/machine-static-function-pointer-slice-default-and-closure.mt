
static VALUES: [i32;2] = [21;2];
static SLICE: read [i32] from static = read VALUES;
static ADDRESS: ptr<read i32> = core.ptr.from_ref(ANSWER);
static ANSWER: i32 = 42;
fn identity(value: i32): i32 { value }
static CALLBACK: fn(i32): i32 = identity;
fn with_default(value: i32 = ANSWER): i32 { value }
fn main() {
    let callback = fn() { ANSWER }
    let reader = fn(): read i32 from static { read ANSWER }
    var total = 0
    for value in SLICE { total += value }
    if CALLBACK(total) == 42 && with_default() == 42 &&
       callback() == 42 && *reader() == 42 && unsafe { *ADDRESS } == 42 { 0 } else { 1 }
}
