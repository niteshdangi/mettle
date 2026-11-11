// profiles: debug release
import alloc.hash_map
import alloc.alloc.Global
import alloc.vec
import core.hash.{BuildHasher, SipHasher}

copy type Builder { pub seed: u64 }
extend Builder implements BuildHasher {
    type Hasher = SipHasher
    fn build_hasher(): SipHasher { core.panic.panic("construction must not hash") }
}

const fn shared_views(): bool {
    let values = [1i32, 2, 3, 4, 5, 6]
    let slice: read [i32] = read values
    match slice.as_array<6usize>() {
        present(array) => { if array[5usize] != 6 { return false } },
        none => { return false }
    }
    match slice.as_array<5usize>() { present(_) => { return false }, none => () }
    match slice.as_array<7usize>() { present(_) => { return false }, none => () }
    match slice.first_chunk<2usize>() {
        present(array) => { if array[1usize] != 2 { return false } },
        none => { return false }
    }
    match slice.last_chunk<2usize>() {
        present(array) => { if array[0usize] != 5 { return false } },
        none => { return false }
    }
    match slice.first_chunk<7usize>() { present(_) => { return false }, none => () }
    match slice.last_chunk<7usize>() { present(_) => { return false }, none => () }
    match slice.split_first_chunk<2usize>() {
        present(parts) => {
            if parts.0[1usize] != 2 || parts.1[0usize] != 3 { return false }
        },
        none => { return false }
    }
    match slice.split_last_chunk<2usize>() {
        present(parts) => {
            if parts.0[3usize] != 4 || parts.1[0usize] != 5 { return false }
        },
        none => { return false }
    }
    match slice.split_first_chunk<7usize>() { present(_) => { return false }, none => () }
    match slice.split_last_chunk<7usize>() { present(_) => { return false }, none => () }
    match slice.split_first_chunk<6usize>() {
        present(parts) => { if parts.1.len() != 0usize { return false } },
        none => { return false }
    }
    match slice.split_last_chunk<6usize>() {
        present(parts) => { if parts.0.len() != 0usize { return false } },
        none => { return false }
    }
    let front = slice.as_chunks<4usize>()
    if front.0.len() != 1usize || front.0[0usize][3usize] != 4 ||
        front.1.len() != 2usize || front.1[0usize] != 5 { return false }
    let back = slice.as_rchunks<4usize>()
    if back.0.len() != 2usize || back.0[1usize] != 2 ||
        back.1.len() != 1usize || back.1[0usize][0usize] != 3 { return false }
    let exact = unsafe { slice.as_chunks_unchecked<3usize>() }
    if exact.len() != 2usize || exact[1usize][2usize] != 6 { return false }
    match slice.first_chunk<0usize>() {
        present(array) => { if array.len() != 0usize { return false } },
        none => { return false }
    }
    match slice.last_chunk<0usize>() {
        present(array) => { if array.len() != 0usize { return false } },
        none => { return false }
    }
    match slice.split_first_chunk<0usize>() {
        present(parts) => { if parts.1.len() != 6usize { return false } },
        none => { return false }
    }
    match slice.split_last_chunk<0usize>() {
        present(parts) => { if parts.0.len() != 6usize { return false } },
        none => { return false }
    }
    let empty: [i32; 0] = []
    let empty_slice: read [i32] = read empty
    let empty_front = empty_slice.as_chunks<1usize>()
    let empty_back = empty_slice.as_rchunks<1usize>()
    match empty_slice.as_array<0usize>() {
        present(array) => array.len() == 0usize &&
            empty_front.0.len() == 0usize && empty_front.1.len() == 0usize &&
            empty_back.0.len() == 0usize && empty_back.1.len() == 0usize,
        none => false
    }
}

const fn mutable_views(): [i32; 8] {
    var values = [1i32, 2, 3, 4, 5, 6, 7, 8]
    let slice: mut [i32] = mut values
    let front = slice.as_chunks_mut<3usize>()
    front.0[0usize][0usize] = 10
    front.0[1usize][2usize] = 60
    front.1[0usize] = 70
    front.1[1usize] = 80
    let back = slice.as_rchunks_mut<3usize>()
    back.0[0usize] = 11
    back.1[0usize][1usize] = 41
    back.1[1usize][2usize] = 81
    let exact = unsafe { slice.as_chunks_unchecked_mut<2usize>() }
    exact[1usize][1usize] = 42
    match take slice.as_mut_array<8usize>() {
        present(array) => { array[2usize] = 32 },
        none => { return [0i32; 8] }
    }
    match take slice.first_chunk_mut<2usize>() {
        present(array) => { array[1usize] = 22 },
        none => { return [0i32; 8] }
    }
    match take slice.last_chunk_mut<2usize>() {
        present(array) => { array[1usize] = 82 },
        none => { return [0i32; 8] }
    }
    match take slice.split_first_chunk_mut<2usize>() {
        present(parts) => {
            parts.0[0usize] = 12
            parts.1[0usize] = 33
        },
        none => { return [0i32; 8] }
    }
    match take slice.split_last_chunk_mut<2usize>() {
        present(parts) => {
            parts.0[0usize] = 13
            parts.1[0usize] = 71
        },
        none => { return [0i32; 8] }
    }
    let range = slice.as_mut_ptr_range()
    unsafe {
        *range.start = 14
        *range.end.sub(1usize) = 83
    }
    match take slice.as_mut_array<7usize>() { present(_) => { return [0i32; 8] }, none => () }
    match take slice.as_mut_array<9usize>() { present(_) => { return [0i32; 8] }, none => () }
    match take slice.first_chunk_mut<9usize>() { present(_) => { return [0i32; 8] }, none => () }
    match take slice.last_chunk_mut<9usize>() { present(_) => { return [0i32; 8] }, none => () }
    match take slice.split_first_chunk_mut<9usize>() { present(_) => { return [0i32; 8] }, none => () }
    match take slice.split_last_chunk_mut<9usize>() { present(_) => { return [0i32; 8] }, none => () }
    match take slice.first_chunk_mut<0usize>() {
        present(array) => { if array.len() != 0usize { return [0i32; 8] } },
        none => { return [0i32; 8] }
    }
    match take slice.last_chunk_mut<0usize>() {
        present(array) => { if array.len() != 0usize { return [0i32; 8] } },
        none => { return [0i32; 8] }
    }
    match take slice.split_first_chunk_mut<0usize>() {
        present(parts) => { if parts.1.len() != 8usize { return [0i32; 8] } },
        none => { return [0i32; 8] }
    }
    match take slice.split_last_chunk_mut<0usize>() {
        present(parts) => { if parts.0.len() != 8usize { return [0i32; 8] } },
        none => { return [0i32; 8] }
    }
    match take slice.split_first_chunk_mut<8usize>() {
        present(parts) => { if parts.1.len() != 0usize { return [0i32; 8] } },
        none => { return [0i32; 8] }
    }
    match take slice.split_last_chunk_mut<8usize>() {
        present(parts) => { if parts.0.len() != 0usize { return [0i32; 8] } },
        none => { return [0i32; 8] }
    }
    values
}

static ITEMS: [i32; 6] = [11, 12, 13, 14, 15, 16]
const fn suffix(): read [i32; 2] from static {
    match ITEMS.last_chunk<2usize>() {
        present(array) => array,
        none => core.panic.panic("unreachable")
    }
}
const fn groups(): read [[i32; 2]] from static {
    let parts = ITEMS.as_chunks<2usize>()
    parts.0
}

const fn vector_views(): (vec.List<i32>, bool) {
    var list = vec.new<i32>()
    var valid = true
    match list.as_array<0usize>() {
        present(array) => { valid = valid && array.len() == 0usize },
        none => { valid = false }
    }
    match list.as_mut_array<0usize>() {
        present(array) => { valid = valid && array.len() == 0usize },
        none => { valid = false }
    }
    match list.first_chunk<0usize>() {
        present(array) => { valid = valid && array.len() == 0usize },
        none => { valid = false }
    }
    match list.first_chunk_mut<0usize>() {
        present(array) => { valid = valid && array.len() == 0usize },
        none => { valid = false }
    }
    match list.last_chunk<0usize>() {
        present(array) => { valid = valid && array.len() == 0usize },
        none => { valid = false }
    }
    match list.last_chunk_mut<0usize>() {
        present(array) => { valid = valid && array.len() == 0usize },
        none => { valid = false }
    }
    match list.split_first_chunk<0usize>() {
        present(parts) => {
            valid = valid && parts.0.len() == 0usize && parts.1.len() == 0usize
        },
        none => { valid = false }
    }
    match list.split_first_chunk_mut<0usize>() {
        present(parts) => {
            valid = valid && parts.0.len() == 0usize && parts.1.len() == 0usize
        },
        none => { valid = false }
    }
    match list.split_last_chunk<0usize>() {
        present(parts) => {
            valid = valid && parts.0.len() == 0usize && parts.1.len() == 0usize
        },
        none => { valid = false }
    }
    match list.split_last_chunk_mut<0usize>() {
        present(parts) => {
            valid = valid && parts.0.len() == 0usize && parts.1.len() == 0usize
        },
        none => { valid = false }
    }
    let front = list.as_chunks<1usize>()
    valid = valid && front.0.len() == 0usize && front.1.len() == 0usize
    let front_mut = list.as_chunks_mut<1usize>()
    valid = valid && front_mut.0.len() == 0usize && front_mut.1.len() == 0usize
    let back = list.as_rchunks<1usize>()
    valid = valid && back.0.len() == 0usize && back.1.len() == 0usize
    let back_mut = list.as_rchunks_mut<1usize>()
    valid = valid && back_mut.0.len() == 0usize && back_mut.1.len() == 0usize
    valid = valid && unsafe { list.as_chunks_unchecked<1usize>().len() == 0usize }
    valid = valid && unsafe { list.as_chunks_unchecked_mut<1usize>().len() == 0usize }
    let range = list.as_mut_ptr_range()
    valid = valid && range.start == range.end
    (take list, valid)
}

static SHARED: bool = shared_views()
static MUTATED: [i32; 8] = mutable_views()
static SUFFIX: read [i32; 2] from static = suffix()
static GROUPS: read [[i32; 2]] from static = groups()
static EMPTY: (vec.List<i32>, bool) = vector_views()
static SET: hash_map.Set<i32, Global, Builder> =
    hash_map.set_with_hasher<i32, Builder>(Builder(0x123456789abcdef0u64))

fn main(): i32 {
    if !SHARED { return 1 }
    if MUTATED[0usize] != 14 || MUTATED[1usize] != 22 ||
        MUTATED[2usize] != 33 || MUTATED[3usize] != 42 ||
        MUTATED[4usize] != 5 || MUTATED[5usize] != 60 ||
        MUTATED[6usize] != 71 || MUTATED[7usize] != 83 { return 2 }
    if SUFFIX[0usize] != 15 || SUFFIX[1usize] != 16 { return 3 }
    if GROUPS.len() != 3usize || GROUPS[2usize][1usize] != 16 { return 4 }
    if !SET.is_empty() || SET.len() != 0usize ||
        SET.hasher().seed != 0x123456789abcdef0u64 { return 5 }
    if !EMPTY.1 || !EMPTY.0.is_empty() { return 6 }
    0
}
