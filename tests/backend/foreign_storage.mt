@layout(C)
copy type SnapshotBytes { data: [u8; 1025] }
@layout(C)
copy type SnapshotWords { data: [u64; 129] }
@layout(transparent)
copy type SnapshotWrapped { value: SnapshotBytes }

fn bump_bytes(value: SnapshotBytes): SnapshotBytes {
    var result = value
    for i in 0usize..1025usize {
        result.data[i] = result.data[i] + (i % 5usize) as u8 + 1u8
    }
    result
}

fn bump_words(value: SnapshotWords): SnapshotWords {
    var result = value
    for i in 0usize..129usize {
        result.data[i] = result.data[i] + (i % 7usize) as u64 + 1u64
    }
    result
}

@export_name("mettle_snapshot_export_bytes")
unsafe extern "C" fn export_bytes(value: SnapshotBytes): SnapshotBytes {
    bump_bytes(value)
}

@export_name("mettle_snapshot_export_words")
unsafe extern "C" fn export_words(value: SnapshotWords): SnapshotWords {
    bump_words(value)
}

@export_name("mettle_snapshot_export_variadic")
unsafe extern "C" fn export_variadic(count: i32, args: ...): SnapshotBytes {
    let value = args.arg<SnapshotBytes>()
    if count == 1 { bump_bytes(value) } else { SnapshotBytes([0u8; 1025]) }
}

extern "C" {
    unsafe fn mettle_c_snapshot_bytes(value: SnapshotBytes): SnapshotBytes;
    unsafe fn mettle_c_snapshot_words(value: SnapshotWords): SnapshotWords;
    unsafe fn mettle_c_snapshot_wrapped(value: SnapshotWrapped): SnapshotWrapped;
    unsafe fn mettle_c_snapshot_variadic_bytes(count: i32, ...): SnapshotBytes;
    unsafe fn mettle_c_snapshot_bytes_callback(
        callback: unsafe extern "C" fn(SnapshotBytes): SnapshotBytes,
        value: SnapshotBytes
    ): i32;
    unsafe fn mettle_c_snapshot_words_callback(
        callback: unsafe extern "C" fn(SnapshotWords): SnapshotWords,
        value: SnapshotWords
    ): i32;
    unsafe fn mettle_c_snapshot_exports(): i32;
}

fn through<T: Copy>(
    value: T, operation: unsafe extern "C" fn(T): T
): T {
    unsafe { operation(value) }
}

fn bytes_match(read original: SnapshotBytes, read observed: SnapshotBytes): bool {
    for i in 0usize..1025usize {
        if observed.data[i] != original.data[i] + (i % 5usize) as u8 + 1u8 {
            return false
        }
    }
    true
}

fn words_match(read original: SnapshotWords, read observed: SnapshotWords): bool {
    for i in 0usize..129usize {
        if observed.data[i] != original.data[i] + (i % 7usize) as u64 + 1u64 {
            return false
        }
    }
    true
}

fn main(): i32 {
    var bytes = SnapshotBytes([0u8; 1025])
    var words = SnapshotWords([0u64; 129])
    for i in 0usize..1025usize { bytes.data[i] = (i % 31usize) as u8 }
    for i in 0usize..129usize { words.data[i] = i as u64 * 17u64 + 2u64 }
    let direct = unsafe { mettle_c_snapshot_bytes(bytes) }
    let aligned = unsafe { mettle_c_snapshot_words(words) }
    if !bytes_match(read bytes, read direct) ||
       !words_match(read words, read aligned) { return 1 }
    let operation: unsafe extern "C" fn(SnapshotBytes): SnapshotBytes =
        mettle_c_snapshot_bytes
    let indirect = unsafe { operation(bytes) }
    let generic = through(bytes, operation)
    if !bytes_match(read bytes, read indirect) ||
       !bytes_match(read bytes, read generic) { return 2 }
    let wrapped = unsafe { mettle_c_snapshot_wrapped(SnapshotWrapped(bytes)) }
    let variadic = unsafe { mettle_c_snapshot_variadic_bytes(1, bytes) }
    if !bytes_match(read bytes, read wrapped.value) ||
       !bytes_match(read bytes, read variadic) { return 3 }
    if unsafe { mettle_c_snapshot_bytes_callback(export_bytes, bytes) } != 1 ||
       unsafe { mettle_c_snapshot_words_callback(export_words, words) } != 1 ||
       unsafe { mettle_c_snapshot_exports() } != 1 { return 4 }
    for i in 0usize..1025usize {
        if bytes.data[i] != (i % 31usize) as u8 { return 5 }
    }
    for i in 0usize..129usize {
        if words.data[i] != i as u64 * 17u64 + 2u64 { return 6 }
    }
    0
}
