// expect-error: ownership 14:17 live exclusive loan
fn set_view<region r>(mut dst: mut [u8] from r, take src: mut [u8] from r): Unit {
    dst = take src
}

fn main(): i32 {
    var first = [1u8, 2u8]
    var second = [3u8, 4u8]
    var views = [mut first[..], mut second[..]]
    var window = mut views[..]
    let (left, right) = window.split_at_mut(1usize)
    let child = mut (*left)[0usize][..]
    set_view(mut (*right)[0usize], take child)
    let value = (*left)[0usize][0usize]
    let still_live = (*right)[0usize].len()
    if value == 0u8 || still_live == 0usize { return 1 }
    0
}
