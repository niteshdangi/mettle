// expect-error: region 10:5 interface
interface Same {}
type Ref<region r> { value: read i32 from r }
type Pair<A, B> { first: A; second: B }
extend<A, B> Pair<A, B> implements Same where (A, A) = (B, B) {}
fn require<T: Same>(read value: T) {}
fn wrong<region a, region b>(
    read first: i32 from a, read second: i32 from b
) {
    require(Pair(Ref(read first), Ref(read second)))
}
fn main(): i32 { 0 }
