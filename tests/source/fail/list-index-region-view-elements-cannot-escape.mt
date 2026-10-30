// expect-error: region 7:5 borrowed source does not outlive the required region
import alloc.vec

fn bad<region r>(source: read i32 from r): read i32 from static {
    var xs = vec.new<read i32 from r>()
    xs.push(source)
    xs[0usize]
}

fn main(): i32 { 0 }
