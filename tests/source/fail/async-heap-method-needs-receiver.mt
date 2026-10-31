// expect-error: signature 3:38 an `async(heap)` method needs a read or mut receiver
interface Source {
    async(heap) static fn make(): i32
}
fn main(): i32 { 0 }
