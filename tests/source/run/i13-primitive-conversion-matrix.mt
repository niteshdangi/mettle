// profiles: debug release
import alloc.vec
import alloc.vec.List
import core.convert.{From, TryFrom}
import core.iter.FromItems

fn from_value<T: From<S>, S>(take value: S): T { T.(From<S>).from(value) }
fn try_value<T: TryFrom<S>, S>(take value: S): (Outcome<T, T.(TryFrom<S>).Error>) { T.(TryFrom<S>).try_from(value) }

fn gather<C: FromItems<X>, X, I: core.iter.OwnedIterable<Item = X>>(take items: I): C { C.(FromItems<X>).from_iter(items) }

fn checks_view<region r>(read items: [i32] from r): bool {
    let viewed: (Outcome<read [i32; 3] from r, core.array.TryFromSliceError>) = try_value(read items)
    viewed.unwrap()[1usize] == 2
}

fn checks_mut<region r>(mut items: [i32] from r): bool {
    let mutable: (Outcome<mut [i32; 3] from r, core.array.TryFromSliceError>) = try_value(mut items)
    var edited = mutable.unwrap()
    edited[0usize] = 9
    true
}

fn main(): i32 {
    let widened_u32: u32 = from_value('A')
    let widened_u64: u64 = from_value('A')
    let widened_u128: u128 = from_value('A')
    if widened_u32 != 65u32 || widened_u64 != 65u64 || widened_u128 != 65u128 { return 1 }
    let narrow_u8: (Outcome<u8, core.char.TryFromCharError>) = try_value('A')
    let narrow_u16: (Outcome<u16, core.char.TryFromCharError>) = try_value('\u{2603}')
    let narrow_usize: (Outcome<usize, core.char.TryFromCharError>) = try_value('A')
    let overflow: (Outcome<u8, core.char.TryFromCharError>) = try_value('\u{2603}')
    if narrow_u8.unwrap() != 65u8 || narrow_u16.unwrap() != 0x2603u16 || narrow_usize.unwrap() != 65usize { return 2 }
    if overflow.is_success() { return 3 }

    let pair: [i32; 1] = from_value((7i32,))
    let single: (i32,) = from_value([7i32])
    if pair[0usize] != 7 || single.0 != 7 { return 4 }

    let source = [1i32, 2i32, 3i32]
    let exact: (Outcome<[i32; 3], core.array.TryFromSliceError>) = try_value(read source[0usize..3usize])
    let wrong: (Outcome<[i32; 2], core.array.TryFromSliceError>) = try_value(read source[0usize..3usize])
    if exact.unwrap()[2usize] != 3 || wrong.is_success() { return 5 }
    if !checks_view(read source[0usize..3usize]) { return 6 }
    var target = [1i32, 2i32, 3i32]
    if !checks_mut(mut target[0usize..3usize]) || target[0usize] != 9 { return 7 }

    let present_items: List<i32?> = List<i32?>.(From<[i32?; 2]>).from([present(1), present(2)])
    let gathered: List<i32>? = gather(present_items)
    let missing_items: List<i32?> = List<i32?>.(From<[i32?; 2]>).from([present(1), none])
    let broken: List<i32>? = gather(missing_items)
    if gathered.unwrap().len() != 2usize || broken.is_present() { return 8 }
    let results: List<(Outcome<i32, i32>)> = List<(Outcome<i32, i32>)>.(From<[(Outcome<i32, i32>); 2]>).from([success(1), success(2)])
    let collected: (Outcome<List<i32>, i32>) = gather(results)
    let failing: List<(Outcome<i32, i32>)> = List<(Outcome<i32, i32>)>.(From<[(Outcome<i32, i32>); 2]>).from([success(1), failure(5)])
    let stopped: (Outcome<List<i32>, i32>) = gather(failing)
    if collected.unwrap().len() != 2usize || !stopped.is_failure() { return 9 }
    0
}
