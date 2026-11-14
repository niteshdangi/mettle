// expect-error: region 5:69 erased owner payload view does not outlive
import alloc.boxed.Heap
interface Show { fn value(): i32; }

fn widen<region r>(take value: Heap<any Show from r>): Heap<any Show> { value }

fn main(): i32 { 0 }
