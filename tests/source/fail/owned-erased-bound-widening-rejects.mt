// expect-error: region 5:69 erased owner payload view does not outlive
import alloc.boxed.Box
interface Show { fn value(): i32; }

fn widen<region r>(take value: Box<any Show from r>): Box<any Show> { value }

fn main(): i32 { 0 }
