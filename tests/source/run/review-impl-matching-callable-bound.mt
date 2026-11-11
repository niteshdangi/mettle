interface Run { fn run<F: fn(): i32>(take f: F): i32; }
interface ReadRun { fn apply<F: fn(read i32): i32>(take f: F): i32; }
interface MapRun { fn map<T, F: fn(T): T>(take f: F): Unit; }
type Runner {}
extend Runner implements Run {
    fn run<F: fn(): i32>(take f: F): i32 { f() }
}
extend Runner implements ReadRun {
    fn apply<F: fn(read i32): i32>(take f: F): i32 { 0 }
}
extend Runner implements MapRun {
    fn map<U, G: fn(U): U>(take f: G): Unit {}
}
fn answer(): i32 { 42 }
fn main(): i32 { Runner().run(answer) - 42 }
