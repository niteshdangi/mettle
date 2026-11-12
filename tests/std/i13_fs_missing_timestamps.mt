import std.fs.{File, FileTimes}
import std.io.{Error, ErrorKind}
import std.path.path_from_text

fn run(): i32 throws Error {
    let path = path_from_text("i13-fs-missing-timestamps")
    let file = try File.create_new(path)
    let first = std.time.system_time_from_parts(1000000000i64, 0u32)
    let accessed = std.time.system_time_from_parts(1000000100i64, 0u32)
    let modified = std.time.system_time_from_parts(1000000200i64, 0u32)
    try file.set_times(FileTimes.new().set_accessed(first).set_accessed(accessed)
        .set_modified(modified))
    let snapshot = try file.metadata()
    assert(try snapshot.accessed() == accessed && snapshot.modified() == modified,
        "timestamp setters overwrite only their selected fields")
    try file.set_times(FileTimes.new())
    let unchanged = try file.metadata()
    assert(try unchanged.accessed() == accessed && unchanged.modified() == modified,
        "omitted timestamps remain unchanged")
    try file.set_modified(first)
    let changed = try file.metadata()
    assert(try changed.accessed() == accessed && changed.modified() == first,
        "modified convenience setter preserves access time")
    assert(try snapshot.accessed() == accessed && snapshot.modified() == modified,
        "metadata timestamps belong to the captured snapshot")
    match take capture changed.created() {
        success(created) => {
            assert(created.subsec_nanos() < 1000000000u32, "available creation time is normalized")
        },
        failure(error) => {
            assert(error.kind().is(ErrorKind.Unsupported), "unavailable creation time is explicit")
        }
    }
    core.mem.drop(take file)
    try std.fs.remove_file(path)
    0
}

fn main(): i32 {
    match take capture run() { success(code) => code, failure(_) => 100 }
}
