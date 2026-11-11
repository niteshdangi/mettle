// expect-error: region 10:5 invariant payload
// expect-error: region 14:5 invariant payload
// expect-error: region 18:5 invariant payload

type MutableRegion<region r> { pointer: ptr<mut (read i32 from r)> }
type MutableGeneric<T> { pointer: ptr<mut T> }
type ReadRegion<region r> { pointer: ptr<read (read i32 from r)> }

fn change_region<region a, region b>(take value: MutableRegion<region a>): MutableRegion<region b> where region a: b {
    return take value
}

fn change_generic<region a, region b>(take value: MutableGeneric<read i32 from a>): MutableGeneric<read i32 from b> where region a: b {
    return take value
}

fn widen_read<region a, region b>(take value: ReadRegion<region a>): ReadRegion<region b> {
    return take value
}

fn main(): i32 { 0 }
