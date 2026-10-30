// expect-error: region 4:65 does not satisfy its declared relationship
import alloc.vec

fn bad<region r>(source: read i32 from r): read i32 from static {
    var xs = vec.new<read i32 from r>()
    xs.push(read source)
    xs[0usize]
}

fn main(): i32 { 0 }
