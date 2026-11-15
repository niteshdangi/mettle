// expect-error: ownership 17:17 live exclusive loan
type Pair<region r> {
    first: mut [u8] from r
    second: mut [u8] from r
}

fn update<region r>(mut pair: Pair<region r>): Unit {
    pair.first = pair.first.split_at_mut(1usize).1
    pair.second = mut pair.first[..]
}

fn main(): i32 {
    var first = [1u8, 2u8, 3u8]
    var second = [4u8, 5u8]
    var pair = Pair(mut first[..], mut second[..])
    update(mut pair)
    let value = pair.first[0usize]
    let still_live = pair.second.len()
    if value == 0u8 || still_live == 0usize { return 1 }
    0
}
