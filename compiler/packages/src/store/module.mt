import alloc.string.{ String, from_text }
import alloc.vec.{ List, new }
import core.text.Text
import std.{ fs, io, process }
import std.io.{ ErrorKind, Reader, Writer }
import std.macros.format
import std.path.{ Path, PathBuf }
import super.sha256.Sha256

pub enum BlobError {
    InvalidDigest;
    Corrupt;
    TooLarge;
    Io(io.Error);
    Cleanup(io.Error, io.Error)
}

pub type BuildLease { lock_file: fs.File }
pub type MaintenanceGuard { lease_directory: PathBuf; gate: fs.File }

fn io_result<T>(take result: Outcome<T, io.Error>): T throws BlobError {
    match take result {
        success(value) => value,
        failure(error) => throw BlobError.Io(error)
    }
}

fn open_lock_file(read path: Path, create: bool): fs.File throws io.Error {
    var options = fs.open_options()
    options.set_read(true)
    options.set_write(true)
    options.set_create(create)
    options.set_mode(384u32)
    let file = try options.open(path)
    if !(try file.metadata()).is_file() { throw io.from_kind(ErrorKind.InvalidData) }
    file
}

fn open_coordination(read root: Path): (PathBuf, fs.File) throws io.Error {
    try fs.create_dir_all(root)
    let canonical = try fs.canonicalize(root)
    let gate = try open_lock_file(canonical.join("native-store.lock"), true)
    (canonical.join("native-leases"), gate)
}

pub fn acquire_build_lease(read root: Path, read key: Text): BuildLease throws io.Error {
    if !valid_sha256_hex(key) { throw io.from_kind(ErrorKind.InvalidInput) }
    let (directory, gate) = try open_coordination(root)
    try gate.lock_shared()
    try fs.create_dir_all(directory)
    let key_file = try open_lock_file(directory.join(key), true)
    try key_file.lock_shared()
    BuildLease(key_file)
}

pub fn try_begin_maintenance(read root: Path): MaintenanceGuard? throws io.Error {
    let (directory, gate) = try open_coordination(root)
    match take capture gate.try_lock() {
        success(_) => present(MaintenanceGuard(directory, gate)),
        failure(fs.TryLockError.WouldBlock) => none,
        failure(fs.TryLockError.Error(error)) => throw error
    }
}

extend MaintenanceGuard {
    pub fn live_keys(): List<String> throws io.Error {
        var live = new<String>()
        var entries = match take capture fs.read_dir(self.lease_directory) {
            success(entries) => entries,
            failure(error) => {
                if error.kind().is(ErrorKind.NotFound) { return live }
                throw error
            }
        }
        while let present(entry) = try entries.next_entry() {
            let name = entry.file_name()
            if let present(key) = name.to_str() {
                if valid_sha256_hex(key) {
                    let path = entry.path()
                    let file = try open_lock_file(path, false)
                    match take capture file.try_lock() {
                        success(_) => { try fs.remove_file(path) },
                        failure(fs.TryLockError.WouldBlock) => { live.push(from_text(key)) },
                        failure(fs.TryLockError.Error(error)) => throw error
                    }
                }
            }
        }
        live
    }
}

pub fn blob_digest(read bytes: [u8]): String {
    var hash = Sha256()
    hash.update(bytes)
    hash.finish()
}

fn blob_directory(read root: Path, read digest: Text): PathBuf {
    root.join("blobs").join(digest.split_at(2usize).0)
}

fn valid_sha256_hex(read digest: Text): bool {
    let bytes = digest.as_bytes()
    if bytes.len() != 64usize { return false }
    for byte in bytes {
        if !(b'0' <= byte && byte <= b'9') && !(b'a' <= byte && byte <= b'f') { return false }
    }
    true
}

pub fn read_blob(read root: Path, read digest: Text, maximum_bytes: usize): List<u8>? throws BlobError {
    if !valid_sha256_hex(digest) { throw BlobError.InvalidDigest }
    let path = blob_directory(root, digest).join(digest)
    match take capture fs.symlink_metadata(path) {
        success(metadata) => { if !metadata.is_file() { throw BlobError.Corrupt } },
        failure(error) => {
            if error.kind().is(ErrorKind.NotFound) { return none }
            throw BlobError.Io(error)
        }
    }
    let file = match take capture fs.open(path) {
        success(file) => file,
        failure(error) => {
            if error.kind().is(ErrorKind.NotFound) { return none }
            throw BlobError.Io(error)
        }
    }
    let metadata = try io_result(capture file.metadata())
    if !metadata.is_file() { throw BlobError.Corrupt }
    if metadata.len() > maximum_bytes as u64 { throw BlobError.TooLarge }
    var bounded = file.`take`(maximum_bytes as u64)
    var bytes = new<u8>()
    let count = try io_result(capture bounded.read_to_end(mut bytes))
    if count == maximum_bytes {
        var extra = [0u8; 1]
        let count = try io_result(capture bounded.get_mut().read_some(mut extra))
        if count != 0usize { throw BlobError.TooLarge }
    }
    let actual = blob_digest(bytes.as_slice())
    if actual.as_text() != digest { throw BlobError.Corrupt }
    present(bytes)
}

fn publish(read temporary: Path, read destination: Path, take file: fs.File, read bytes: [u8]): Unit throws io.Error {
    {
        var out = take file
        try out.write_all(bytes)
        try out.set_permissions(fs.permissions_from_mode(292u32))
        try out.sync_all()
    }
    try fs.rename(temporary, destination)
}

pub fn write_blob(read root: Path, read bytes: [u8]): String throws BlobError {
    let digest = blob_digest(bytes)
    let directory = blob_directory(root, digest.as_text())
    let destination = directory.join(digest.as_text())
    try io_result(capture fs.create_dir_all(directory))
    let pid = process.id()
    var slot = 0usize
    loop {
        let temporary = directory.join(format(f".{digest}.{pid}.{slot}.tmp"))
        match take capture fs.create_new(temporary) {
            success(file) => {
                match take capture publish(temporary, destination, take file, bytes) {
                    success(_) => { return digest },
                    failure(error) => {
                        match take capture fs.remove_file(temporary) {
                            success(_) => throw BlobError.Io(error),
                            failure(cleanup) => throw BlobError.Cleanup(error, cleanup)
                        }
                    }
                }
            },
            failure(error) => {
                if !error.kind().is(ErrorKind.AlreadyExists) { throw BlobError.Io(error) }
                slot += 1usize
            }
        }
    }
}

@test
fn blob_read_integrity(): Unit throws BlobError {
    let pid = process.id()
    let root = std.env.temp_dir().join(format(f"mettle-blob-integrity-{pid}"))
    let payload = [0u8, 255u8, 10u8]
    let digest = blob_digest(payload)
    let missing = try read_blob(root, digest.as_text(), 3usize)
    assert(missing.is_none(), "absent blob must be a miss")
    assert(!(try io_result(capture fs.try_exists(root))), "reading a miss created the store")
    match take capture read_blob(root, "../blobs", 3usize) {
        failure(BlobError.InvalidDigest) => (),
        _ => assert(false, "invalid digest was not rejected")
    }
    let stored = try write_blob(root, payload)
    assert(stored.as_text() == digest.as_text(), "wrong content address")
    let result = try read_blob(root, stored.as_text(), 3usize)
    assert(result.or_panic().as_slice() == payload, "blob changed on round trip")
    match take capture read_blob(root, stored.as_text(), 2usize) {
        failure(BlobError.TooLarge) => (),
        _ => assert(false, "oversize blob was not rejected")
    }
    let path = blob_directory(root, digest.as_text()).join(digest.as_text())
    try io_result(capture fs.remove_file(path))
    try io_result(capture fs.write(path, [0u8, 254u8, 10u8]))
    match take capture read_blob(root, stored.as_text(), 3usize) {
        failure(BlobError.Corrupt) => (),
        _ => assert(false, "same-length corruption was not detected")
    }
    let _ = try write_blob(root, payload)
    let repaired = try read_blob(root, stored.as_text(), 3usize)
    assert(repaired.or_panic().as_slice() == payload, "republishing did not repair the blob")
    try io_result(capture fs.remove_dir_all(root))
}

@test
fn blob_publication_failure(): Unit throws BlobError {
    let pid = process.id()
    let root = std.env.temp_dir().join(format(f"mettle-blob-publication-{pid}"))
    try io_result(capture fs.create_dir(root))
    let payload = "artifact".as_bytes()
    let digest = blob_digest(payload)
    let directory = blob_directory(root, digest.as_text())
    let destination = directory.join(digest.as_text())
    try io_result(capture fs.create_dir_all(destination))
    let marker = destination.join("keep")
    try io_result(capture fs.write(marker, [42u8]))
    let occupied = directory.join(format(f".{digest}.{pid}.0.tmp"))
    try io_result(capture fs.write(occupied, [17u8]))
    match take capture write_blob(root, payload) {
        failure(BlobError.Io(_)) => (),
        _ => assert(false, "blocked rename must fail")
    }
    let preserved = try io_result(capture fs.read_bytes(marker))
    assert(preserved.as_slice() == [42u8], "failed publication changed the destination")
    let untouched = try io_result(capture fs.read_bytes(occupied))
    assert(untouched.as_slice() == [17u8], "writer touched another staging file")
    let leaked = try io_result(capture fs.try_exists(directory.join(format(f".{digest}.{pid}.1.tmp"))))
    assert(!leaked, "failed publication left its staging file")
    try io_result(capture fs.remove_dir_all(root))
}

fn fail_with_build_lease(read root: Path, read key: Text): Unit throws io.Error {
    let _lease = try acquire_build_lease(root, key)
    throw io.from_kind(ErrorKind.InvalidData)
}

@test
fn lease_lifecycle(): Unit throws io.Error {
    let pid = process.id()
    let root = std.env.temp_dir().join(format(f"mettle-blob-leases-{pid}"))
    try fs.create_dir(root)
    let a = blob_digest([1u8])
    let b = blob_digest([2u8])
    let first = try acquire_build_lease(root, a.as_text())
    let second = try acquire_build_lease(root, a.as_text())
    match take capture fail_with_build_lease(root, b.as_text()) {
        success(_) => assert(false, "expected a failed build"),
        failure(error) => assert(error.kind().is(ErrorKind.InvalidData), "failed to acquire B")
    }
    core.mem.drop(take first)
    {
        let maintenance = (try try_begin_maintenance(root)).or_panic()
        assert((try try_begin_maintenance(root)).is_none(), "two maintenance guards overlapped")
        let live = try maintenance.live_keys()
        assert(live.len() == 1 && live[0].as_text() == a.as_text(),
            "maintenance must protect A but not failed build B")
    }
    let third = try acquire_build_lease(root, b.as_text())
    core.mem.drop(take second)
    {
        let maintenance = (try try_begin_maintenance(root)).or_panic()
        let live = try maintenance.live_keys()
        assert(live.len() == 1 && live[0].as_text() == b.as_text(), "reacquired B was not protected")
    }
    core.mem.drop(take third)
    {
        let maintenance = (try try_begin_maintenance(root)).or_panic()
        let live = try maintenance.live_keys()
        assert(live.is_empty(), "released build leases still prevent clean")
    }
    try fs.remove_dir_all(root)
}

@test
fn known_sha256_vectors(): Unit {
    let empty = blob_digest("".as_bytes())
    assert(empty.as_text() == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        "wrong empty digest")
    let two_padding_blocks = blob_digest("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".as_bytes())
    assert(two_padding_blocks.as_text() == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
        "wrong 56-byte digest")
    let bytes = [0u8; 64]
    let aligned = blob_digest(bytes)
    assert(aligned.as_text() == "f5a5fd42d16a20302798ef6ed309979b43003d2320d9f0e8ea9831a92759fb4b",
        "wrong 64-byte digest")
    var stream = Sha256()
    stream.update(bytes[..1])
    stream.update(bytes[1..])
    let split = stream.finish()
    assert(split.as_text() == aligned.as_text(), "splitting an update changed the digest")
}
