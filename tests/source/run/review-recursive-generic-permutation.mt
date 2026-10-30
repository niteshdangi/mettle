
copy type Pair<A:Copy,B:Copy> { first:A; second:B }
fn recurse<T:Copy,U:Copy>(p:Pair<T,U>,q:Pair<U,T>,n:i32):T {
    if n == 0 { p.first } else {
        let other = recurse::<U,T>(q,p,n-1)
        p.first
    }
}
fn main() { recurse(Pair(0,2u8),Pair(3u8,4),1) }
