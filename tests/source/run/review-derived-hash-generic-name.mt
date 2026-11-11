import core.hash.hash_one
@derive(Hash)
type Wrapper<__H, __H_> { left: __H; right: __H_ }
fn main(): i32 {
    let value = Wrapper(20, 22)
    if hash_one(read value) == hash_one(read Wrapper(20, 22)) { 0 } else { 1 }
}
