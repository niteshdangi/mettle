import alloc.string.{ String, from_text, from_utf8_lossy }
import core.text.Text
import std.{ env, fs, io, process }
import std.ffi.os_str_from_text
import std.macros.format
import std.path.{ Path, PathBuf, path_buf_from_bytes, new_path_buf }
import super.data.Range
import super.inputs.{ PackageError, PackagePhase, error_at, io_result }
import super.sha256.Sha256

pub type Checkout { pub directory: PathBuf; pub commit: String }

fn cache_root(read configured: PathBuf?): PathBuf {
    if let present(path) = configured {
        if !path.is_empty() { return path.to_path_buf() }
    }
    if let present(path) = env.var_os(os_str_from_text("METTLE_CACHE_DIR")) {
        if !path.as_bytes().is_empty() { return path_buf_from_bytes(path.as_bytes()) }
    }
    if let present(path) = env.var_os(os_str_from_text("XDG_CACHE_HOME")) {
        if !path.as_bytes().is_empty() { return path_buf_from_bytes(path.as_bytes()).join("mettle") }
    }
    if let present(home) = env.home_dir() { return home.join(".cache/mettle") }
    new_path_buf()
}

fn command(): process.Command {
    var git = process.command_text("git")
    git.arg_text("-c")
    git.arg_text("core.hooksPath=/dev/null")
    git.arg_text("-c")
    git.arg_text("protocol.ext.allow=never")
    git.env(os_str_from_text("GIT_TERMINAL_PROMPT"), os_str_from_text("0"))
    git.env(os_str_from_text("GIT_NO_LAZY_FETCH"), os_str_from_text("1"))
    git.env_remove(os_str_from_text("GIT_DIR"))
    git.env_remove(os_str_from_text("GIT_WORK_TREE"))
    let _ = git.stdin(process.Stdio.Null)
    git
}

fn run(mut git: process.Command, read operation: Text, read path: Path, span: Range): String throws PackageError {
    let output = try io_result(take capture git.output(), path, span, PackagePhase.Package)
    if !output.status.succeeded() {
        let status = output.status
        throw error_at(path, span, format(f"git {operation} failed ({status})"), PackagePhase.Package)
    }
    from_utf8_lossy(output.stdout.as_slice())
}

fn exists(read file: Path, read path: Path, span: Range): bool throws PackageError {
    match take capture fs.symlink_metadata(file) {
        success(_) => true,
        failure(issue) => match issue.kind() {
            io.ErrorKind.NotFound => false,
            _ => { throw error_at(path, span, issue.message(), PackagePhase.Package) }
        }
    }
}

fn clear_stage(read directory: Path, read path: Path, span: Range): Unit throws PackageError {
    if try exists(directory, path, span) {
        try io_result(take capture fs.remove_dir_all(directory), path, span, PackagePhase.Package)
    }
}

fn is_commit(read text: Text): bool {
    if text.len() != 40 && text.len() != 64 { return false }
    for byte in text.as_bytes() {
        if !(byte >= b'0' && byte <= b'9') && !(byte >= b'a' && byte <= b'f') { return false }
    }
    true
}

fn resolve_commit(read directory: Path, read expression: Text, read path: Path, span: Range): String throws PackageError {
    var git = command()
    git.arg_text("-C")
    git.arg(directory.as_os_str())
    for option in ["rev-parse", "--verify", "--end-of-options"] { git.arg_text(option) }
    git.arg_text(expression)
    let output = try run(mut git, "rev-parse", path, span)
    let commit = output.as_text().trim_end()
    if !is_commit(commit) { throw error_at(path, span, from_text("git did not return a commit object ID"), PackagePhase.Package) }
    from_text(commit)
}

fn validate_checkout(read directory: Path, read commit: Text, read path: Path, span: Range): Unit throws PackageError {
    let head = try resolve_commit(directory, "HEAD^{commit}", path, span)
    if head.as_text() != commit {
        throw error_at(path, span, format(f"cached checkout does not match commit {commit}"), PackagePhase.Package)
    }
    var git = command()
    git.arg_text("-C")
    git.arg(directory.as_os_str())
    for option in ["status", "--porcelain", "--untracked-files=all"] { git.arg_text(option) }
    let status = try run(mut git, "status", path, span)
    if !status.is_empty() {
        throw error_at(path, span, from_text("cached checkout contains modified or untracked files"), PackagePhase.Package)
    }
}

pub fn checkout(read configured: PathBuf?, offline: bool, read url: Text, read selector: Text,
        read locked_commit: Text, read path: Path, span: Range): Checkout throws PackageError {
    let store = cache_root(configured).join("sources/git")
    let mirrors = store.join("mirrors")
    try io_result(take capture fs.create_dir_all(mirrors), path, span, PackagePhase.Package)
    let root = try io_result(take capture fs.canonicalize(store), path, span, PackagePhase.Package)
    var hash = Sha256()
    hash.update(url.as_bytes())
    let digest = hash.finish()
    let key = digest.as_text()
    let mirror = root.join("mirrors").join(key)
    let lock_path = root.join("mirrors").join(format(f"{key}.lock").as_text())
    var options = fs.open_options()
    options.write(true)
    options.create(true)
    let guard = try io_result(take capture options.open(lock_path), path, span, PackagePhase.Package)
    try io_result(take capture guard.lock(), path, span, PackagePhase.Package)
    if !(try exists(mirror.as_path(), path, span)) {
        if offline {
            throw error_at(path, span, from_text("offline mode has no cached repository"), PackagePhase.Package)
        }
        let stage = root.join("mirrors").join(format(f"{key}.partial").as_text())
        try clear_stage(stage.as_path(), path, span)
        var git = command()
        for option in ["clone", "--mirror", "--"] { git.arg_text(option) }
        git.arg_text(url)
        git.arg(stage.as_os_str())
        let _ = try run(mut git, "clone --mirror", path, span)
        try io_result(take capture fs.rename(stage, mirror), path, span, PackagePhase.Package)
    } else if !offline {
        var git = command()
        git.arg_text("-C")
        git.arg(mirror.as_os_str())
        for option in ["fetch", "--tags", "origin"] { git.arg_text(option) }
        let _ = try run(mut git, "fetch", path, span)
    }
    var revision = if offline && !locked_commit.is_empty() {
        if !is_commit(locked_commit) {
            throw error_at(path, span, from_text("lock contains an invalid Git commit object ID"), PackagePhase.Lock)
        }
        from_text(locked_commit)
    } else if let present(rev) = selector.strip_prefix("rev=") { from_text(rev) }
    else if let present(tag) = selector.strip_prefix("tag=") { format(f"refs/tags/{tag}") }
    else if let present(branch_name) = selector.strip_prefix("branch=") { format(f"refs/heads/{branch_name}") }
    else { from_text("HEAD") }
    revision.push_str("^{commit}")
    let commit_id = try resolve_commit(mirror.as_path(), revision.as_text(), path, span)
    let commit = commit_id.as_text()
    let checkouts = root.join("checkouts").join(key)
    let destination = checkouts.join(commit)
    if try exists(destination.as_path(), path, span) {
        try validate_checkout(destination.as_path(), commit, path, span)
    } else {
        try io_result(take capture fs.create_dir_all(checkouts), path, span, PackagePhase.Package)
        let stage = checkouts.join(format(f"{commit}.partial").as_text())
        try clear_stage(stage.as_path(), path, span)
        var clone = command()
        for option in ["clone", "--shared", "--no-checkout", "--"] { clone.arg_text(option) }
        clone.arg(mirror.as_os_str())
        clone.arg(stage.as_os_str())
        let _ = try run(mut clone, "clone --shared", path, span)
        var detach = command()
        detach.arg_text("-C")
        detach.arg(stage.as_os_str())
        detach.arg_text("checkout")
        detach.arg_text("--detach")
        detach.arg_text(commit)
        let _ = try run(mut detach, "checkout --detach", path, span)
        try validate_checkout(stage.as_path(), commit, path, span)
        try io_result(take capture fs.rename(stage, destination), path, span, PackagePhase.Package)
    }
    let directory = try io_result(take capture fs.canonicalize(destination), path, span, PackagePhase.Package)
    try io_result(take capture guard.unlock(), path, span, PackagePhase.Package)
    Checkout(take directory, take commit_id)
}
