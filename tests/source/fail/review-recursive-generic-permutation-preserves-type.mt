// expect-error: type 7:9 expected U, found T

copy type Pair<A:Copy,B:Copy> { first:A; second:B }
fn swap<T:Copy,U:Copy>(p:Pair<T,U>,q:Pair<U,T>,n:i32):T {
    if n == 0 { p.first } else {
        let other = swap<U,T>(q,p,n-1)
        q.first
    }
}
fn main() { 0 }
