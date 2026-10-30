// expect-error: region 6:36 invariant payload

type Ref<region r> { value: mut (read i32 from r) from r }
fn bad<region a, region b>(
    value: take Ref<region a>
): Ref<region b> where region a: b { take value }
fn main() { 0 }
