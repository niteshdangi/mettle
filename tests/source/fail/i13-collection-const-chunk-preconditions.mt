// profiles: debug release
// expect-error: constant 15:5 panic during constant evaluation
// expect-error: constant 20:5 panic during constant evaluation
// expect-error: constant 25:5 panic during constant evaluation
// expect-error: constant 30:5 panic during constant evaluation
// expect-error: constant 35:14 panic during constant evaluation
// expect-error: constant 40:14 panic during constant evaluation
// expect-error: constant 45:14 panic during constant evaluation
// expect-error: constant 50:14 panic during constant evaluation
// expect-error-count: 8

static ZERO_CHUNKS: usize = {
    let values = [1i32; 3]
    let slice: read [i32] = read values
    slice.as_chunks<0usize>().0.len()
}
static ZERO_CHUNKS_MUT: usize = {
    var values = [1i32; 3]
    let slice: mut [i32] = mut values
    slice.as_chunks_mut<0usize>().0.len()
}
static ZERO_RCHUNKS: usize = {
    let values = [1i32; 3]
    let slice: read [i32] = read values
    slice.as_rchunks<0usize>().1.len()
}
static ZERO_RCHUNKS_MUT: usize = {
    var values = [1i32; 3]
    let slice: mut [i32] = mut values
    slice.as_rchunks_mut<0usize>().1.len()
}
static ZERO_UNCHECKED: usize = {
    let values = [1i32; 3]
    let slice: read [i32] = read values
    unsafe { slice.as_chunks_unchecked<0usize>().len() }
}
static ZERO_UNCHECKED_MUT: usize = {
    var values = [1i32; 3]
    let slice: mut [i32] = mut values
    unsafe { slice.as_chunks_unchecked_mut<0usize>().len() }
}
static NONDIVIDING_UNCHECKED: usize = {
    let values = [1i32; 3]
    let slice: read [i32] = read values
    unsafe { slice.as_chunks_unchecked<2usize>().len() }
}
static NONDIVIDING_UNCHECKED_MUT: usize = {
    var values = [1i32; 3]
    let slice: mut [i32] = mut values
    unsafe { slice.as_chunks_unchecked_mut<2usize>().len() }
}
