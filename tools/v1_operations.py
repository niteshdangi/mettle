#!/usr/bin/env python3
"""Select the V1 operation subset from the pinned Rust inventory.

Applies docs/library-surface.md section 6.1 to docs/baseline/operations.jsonl.gz
and writes docs/baseline/v1-operations.csv. Integer widths, float widths and
same-shape integer atomics fold into one family each. Trait implementations
are one row per selected (type, trait) pair.

Status and the evidence-test column are kept when a family already exists in
the output, so regeneration does not wipe declaration or evidence notes.
"""

import csv
import gzip
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs" / "baseline" / "operations.jsonl.gz"
OUTPUT = ROOT / "docs" / "baseline" / "v1-operations.csv"
COLUMNS = [
    "canonical_id",
    "family",
    "Rust contract",
    "Mettle path",
    "status",
    "evidence test",
]

INTEGERS = {
    "i8", "i16", "i32", "i64", "i128", "isize",
    "u8", "u16", "u32", "u64", "u128", "usize",
}
FLOATS = {"f32", "f64"}
INTEGER_ATOMICS = {
    "AtomicI32", "AtomicU32", "AtomicI64", "AtomicU64",
    "AtomicIsize", "AtomicUsize",
}
PRIMITIVES = INTEGERS | FLOATS | {"bool", "char", "str", "slice", "array", "tuple", "unit"}

# Rust name -> Mettle name. Only names section 9 renames, plus Deque, which
# is the library's name for VecDeque.
SEGMENT_RENAMES = {
    "Vec": "List",
    "HashMap": "Map",
    "HashSet": "Set",
    "BTreeMap": "SortedMap",
    "BTreeSet": "SortedSet",
    "VecDeque": "Deque",
    "IntoIterator": "OwnedIterable",
    "DoubleEndedIterator": "BidirectionalIterator",
    "FromIterator": "FromItems",
    "Extend": "ExtendItems",
    "BufReader": "BufferedReader",
    "BufWriter": "BufferedWriter",
}
ADAPTER_RENAMES = {
    "Map": "Mapped",
    "Filter": "Filtered",
    "FilterMap": "FilterMapped",
    "Enumerate": "Enumerated",
    "Zip": "Zipped",
    "Chain": "Chained",
    "Rev": "Reversed",
    "Take": "Limited",
    "Skip": "Skipped",
    "TakeWhile": "TakenWhile",
    "SkipWhile": "SkippedWhile",
    "StepBy": "Stepped",
    "FlatMap": "FlatMapped",
    "Flatten": "Flattened",
    "Cloned": "Cloned",
    "Copied": "Copied",
}
IO_RENAMES = {"Read": "Reader", "Write": "Writer"}

TYPE_SUFFIXES = {
    ("option", "Option"), ("result", "Result"), ("ops", "Range"),
    ("ops", "RangeInclusive"), ("range", "Range"), ("range", "RangeInclusive"),
    ("mem", "ManuallyDrop"), ("ptr", "NonNull"), ("marker", "PhantomData"),
    ("cmp", "Reverse"), ("cmp", "Ordering"), ("num", "Wrapping"),
    ("string", "String"), ("vec", "Vec"), ("vec_deque", "VecDeque"),
    ("hash_map", "HashMap"), ("hash_set", "HashSet"), ("btree_map", "BTreeMap"),
    ("btree_set", "BTreeSet"), ("binary_heap", "BinaryHeap"), ("boxed", "Box"),
    ("rc", "Rc"), ("rc", "Weak"), ("sync", "Arc"), ("sync", "Weak"),
    ("cell", "Cell"), ("cell", "RefCell"), ("cell", "Ref"), ("cell", "RefMut"),
    ("cell", "OnceCell"), ("pin", "Pin"), ("sync", "Mutex"),
    ("sync", "MutexGuard"), ("sync", "RwLock"), ("sync", "RwLockReadGuard"),
    ("sync", "RwLockWriteGuard"), ("sync", "Condvar"), ("sync", "Once"),
    ("sync", "OnceLock"), ("sync", "Barrier"), ("atomic", "AtomicBool"),
    ("atomic", "AtomicPtr"), ("atomic", "AtomicI32"), ("atomic", "AtomicU32"),
    ("atomic", "AtomicI64"), ("atomic", "AtomicU64"), ("atomic", "AtomicIsize"),
    ("atomic", "AtomicUsize"), ("atomic", "Ordering"), ("mpsc", "Sender"),
    ("mpsc", "SyncSender"), ("mpsc", "Receiver"), ("time", "Duration"),
    ("time", "Instant"), ("time", "SystemTime"), ("fmt", "Formatter"),
    ("fmt", "Arguments"), ("io", "Error"), ("io", "ErrorKind"), ("fs", "File"),
    ("fs", "OpenOptions"), ("fs", "Metadata"), ("fs", "ReadDir"),
    ("fs", "DirEntry"), ("fs", "FileType"), ("fs", "Permissions"),
    ("path", "Path"), ("path", "PathBuf"), ("ffi", "OsStr"), ("ffi", "OsString"),
    ("ffi", "CStr"), ("ffi", "CString"), ("io", "Stdin"), ("io", "Stdout"),
    ("io", "Stderr"), ("io", "BufReader"), ("io", "BufWriter"), ("io", "Lines"),
    ("io", "Cursor"), ("process", "Command"), ("process", "Child"),
    ("process", "Output"), ("process", "ExitStatus"), ("process", "Stdio"),
    ("net", "TcpListener"), ("net", "TcpStream"), ("net", "UdpSocket"),
    ("net", "SocketAddr"), ("net", "IpAddr"), ("net", "Ipv4Addr"),
    ("net", "Ipv6Addr"), ("thread", "JoinHandle"), ("thread", "Thread"),
    ("thread", "Scope"), ("thread", "ScopedJoinHandle"), ("task", "Poll"),
    ("task", "Context"), ("task", "Waker"),
}
COLLECTION_MODULES = {
    "string", "vec", "vec_deque", "hash_map", "hash_set", "btree_map",
    "btree_set", "binary_heap",
}
COLLECTION_CHILDREN = {
    "Entry", "Iter", "IterMut", "IntoIter", "Drain", "Keys", "Values",
}
ADAPTERS = {
    ("iter", "Map"), ("iter", "Filter"), ("iter", "Enumerate"), ("iter", "Zip"),
    ("iter", "Chain"), ("iter", "Rev"), ("iter", "Take"), ("iter", "Skip"),
    ("iter", "Peekable"), ("iter", "StepBy"), ("iter", "TakeWhile"),
    ("iter", "SkipWhile"), ("iter", "FlatMap"), ("iter", "Flatten"),
    ("iter", "Cloned"), ("iter", "Copied"), ("slice", "Windows"),
    ("slice", "Chunks"),     ("str", "Chars"), ("str", "CharIndices"),
    ("str", "Bytes"), ("str", "Split"), ("str", "SplitWhitespace"),
    ("slice", "Iter"), ("slice", "IterMut"),
}
TRAIT_SUFFIXES = {
    ("iter", "Iterator"), ("iter", "IntoIterator"),
    ("iter", "DoubleEndedIterator"), ("iter", "ExactSizeIterator"),
    ("iter", "FromIterator"), ("iter", "Extend"), ("clone", "Clone"),
    ("marker", "Copy"), ("marker", "Send"), ("marker", "Sync"),
    ("marker", "Sized"), ("default", "Default"), ("fmt", "Debug"),
    ("fmt", "Display"), ("fmt", "Write"), ("hash", "Hash"), ("hash", "Hasher"),
    ("hash", "BuildHasher"), ("cmp", "PartialEq"), ("cmp", "Eq"),
    ("cmp", "PartialOrd"), ("cmp", "Ord"), ("io", "Read"), ("io", "Write"),
    ("io", "BufRead"), ("io", "Seek"), ("convert", "From"), ("convert", "Into"),
    ("convert", "TryFrom"), ("convert", "TryInto"), ("convert", "AsRef"),
    ("convert", "AsMut"), ("borrow", "Borrow"), ("borrow", "ToOwned"),
    ("string", "ToString"), ("str", "FromStr"), ("ops", "Add"), ("ops", "Sub"),
    ("ops", "Mul"), ("ops", "Div"), ("ops", "Rem"), ("ops", "Neg"),
    ("ops", "Not"), ("ops", "BitAnd"), ("ops", "BitOr"), ("ops", "BitXor"),
    ("ops", "Shl"), ("ops", "Shr"), ("ops", "AddAssign"), ("ops", "SubAssign"),
    ("ops", "MulAssign"), ("ops", "DivAssign"), ("ops", "RemAssign"),
    ("ops", "BitAndAssign"), ("ops", "BitOrAssign"), ("ops", "BitXorAssign"),
    ("ops", "ShlAssign"), ("ops", "ShrAssign"), ("ops", "Index"),
    ("ops", "IndexMut"), ("ops", "Deref"), ("ops", "DerefMut"), ("ops", "Drop"),
    ("ops", "Fn"), ("ops", "FnMut"), ("ops", "FnOnce"), ("future", "Future"),
    ("error", "Error"), ("any", "Any"),
}
FREE_FUNCTIONS = {
    ("thread", "spawn"), ("thread", "scope"), ("thread", "sleep"),
    ("thread", "current"), ("thread", "yield_now"),
    ("thread", "available_parallelism"),
    ("fs", "read"), ("fs", "read_to_string"), ("fs", "write"),
    ("fs", "create_dir"), ("fs", "create_dir_all"), ("fs", "remove_file"),
    ("fs", "remove_dir"), ("fs", "remove_dir_all"), ("fs", "rename"),
    ("fs", "copy"), ("fs", "metadata"), ("fs", "read_dir"),
    ("fs", "canonicalize"),
    ("env", "args"), ("env", "var"), ("env", "vars"), ("env", "set_var"),
    ("env", "remove_var"), ("env", "current_dir"), ("env", "set_current_dir"),
    ("env", "temp_dir"),
    ("process", "exit"), ("process", "abort"), ("process", "id"),
    ("io", "stdin"), ("io", "stdout"), ("io", "stderr"), ("io", "copy"),
    ("mem", "swap"), ("mem", "replace"), ("mem", "take"), ("mem", "drop"),
    ("mem", "forget"), ("mem", "size_of"), ("mem", "align_of"),
    ("mem", "size_of_val"),
    ("ptr", "null"), ("ptr", "null_mut"), ("ptr", "eq"), ("ptr", "read"),
    ("ptr", "write"), ("ptr", "copy"), ("ptr", "copy_nonoverlapping"),
    ("ptr", "drop_in_place"),
    ("cmp", "min"), ("cmp", "max"),
    ("iter", "once"), ("iter", "repeat"), ("iter", "empty"),
    ("iter", "from_fn"), ("iter", "successors"), ("iter", "zip"),
    ("mpsc", "channel"), ("mpsc", "sync_channel"),
    ("hint", "black_box"),
    ("char", "from_u32"), ("char", "from_digit"),
    ("str", "from_utf8"),
    ("array", "from_fn"),
}
MACROS = {
    "print", "println", "eprint", "eprintln", "format", "format_args",
    "write", "writeln", "assert", "assert_eq", "assert_ne", "debug_assert",
    "debug_assert_eq", "debug_assert_ne", "panic", "vec", "unreachable",
    "todo", "unimplemented", "matches", "dbg",
}
UNIX_OS = {"unix", "fd", "raw"}
DARWIN_TRUE = {
    "aarch64", "arm64", "macos", "darwin", "apple", "unix", "little-endian",
    "neon",
}
INHERENT_KINDS = {"method", "associatedconstant", "variant", "structfield"}
TRAIT_MEMBER_KINDS = {
    "method", "tymethod", "associatedconstant", "associatedtype",
}


def parts_of(path):
    return path.split("::")


def excluded_module(path):
    parts = parts_of(path)
    if "arch" in parts:
        return True
    if "os" in parts:
        index = parts.index("os")
        if index + 1 < len(parts) and parts[index + 1] not in UNIX_OS:
            return True
    return False


def page_name(url):
    leaf = url.split("#", 1)[0].rstrip("/").rsplit("/", 1)[-1]
    if leaf.endswith(".html"):
        leaf = leaf[:-5]
    if "." in leaf:
        return leaf.split(".", 1)[1]
    return leaf


def selected_type_name(path, kind):
    parts = parts_of(path)
    name = parts[-1] if parts else ""
    # Integer and pointer atomics are stable type aliases, not structs.
    if kind == "type":
        if len(parts) >= 2 and (parts[-2], name) in TYPE_SUFFIXES:
            return name
        return None
    if kind not in {"struct", "enum", "union", "primitive"}:
        return None
    if kind == "primitive":
        return name if name in PRIMITIVES else None
    if len(parts) >= 2 and (parts[-2], name) in ADAPTERS:
        return name
    if len(parts) >= 2 and parts[-2] in COLLECTION_MODULES and name in COLLECTION_CHILDREN:
        return name
    if len(parts) >= 2 and (parts[-2], name) in TYPE_SUFFIXES:
        return name
    return None


def selected_trait_name(path, kind):
    if kind != "trait":
        return None
    parts = parts_of(path)
    if len(parts) < 2 or (parts[-2], parts[-1]) not in TRAIT_SUFFIXES:
        return None
    return parts[-1]


def self_type(signature):
    body = signature.split("where", 1)[0]
    if " for " not in body:
        return None
    name = body.rsplit(" for ", 1)[1].strip().rstrip(",")
    if name.startswith(("&", "*")):
        return None
    if name.startswith("["):
        return "array" if ";" in name else "slice"
    if name.startswith("("):
        return "unit" if name == "()" else "tuple"
    base = name.split("<", 1)[0].split("::")[-1].strip()
    if not base or base in {"T", "Self", "U"} or (len(base) == 1 and base.isupper()):
        return None
    return base


def fold_token(name):
    if name in INTEGERS:
        return "{integer}"
    if name in FLOATS:
        return "{float}"
    if name in INTEGER_ATOMICS:
        return "{atomic}"
    return name


def mettle_segments(path):
    parts = parts_of(path)
    renamed = []
    for index, part in enumerate(parts):
        if part in SEGMENT_RENAMES:
            part = SEGMENT_RENAMES[part]
        elif (index > 0 and parts[index - 1] == "iter" and part in ADAPTER_RENAMES):
            part = ADAPTER_RENAMES[part]
        elif index > 0 and parts[index - 1] == "io" and part in IO_RENAMES:
            part = IO_RENAMES[part]
        renamed.append(part)
    return renamed


def mettle_path(path):
    return ".".join(mettle_segments(path))


def fold_path(path):
    parts = mettle_segments(path)
    if parts and parts[0] in {"core", "alloc", "std"}:
        parts = parts[1:]
    return ".".join(fold_token(part) for part in parts)


def path_rank(path):
    if path.startswith("core."):
        return 0
    if path.startswith("alloc."):
        return 1
    if path.startswith("std."):
        return 2
    return 3


def darwin_alternative(text):
    text = text.strip()
    if not text:
        return False
    if text.startswith("(") and text.endswith(")"):
        return darwin_clause(text[1:-1])
    lower = text.lower().replace(" ", "-")
    if lower.startswith("target-feature-") or lower.startswith("target-feature"):
        feature = lower.split("feature", 1)[-1].strip("- ")
        return feature == "neon"
    token = lower.strip()
    if token in DARWIN_TRUE:
        return True
    if token in {"arm64ec"}:
        return False
    if token.startswith("non-"):
        return not darwin_alternative(token[4:])
    width = ""
    if token.startswith("target_has_atomic_load_store="):
        width = token.split("=", 1)[1]
    elif token.startswith("target_has_atomic="):
        width = token.split("=", 1)[1]
    if width in {"8", "16", "32", "64", "128", "ptr"}:
        return True
    return False


def split_top(text, separator):
    pieces = []
    depth = 0
    start = 0
    index = 0
    while index < len(text):
        char = text[index]
        if char == "(":
            depth += 1
        elif char == ")":
            depth = max(0, depth - 1)
        elif depth == 0 and text.startswith(separator, index):
            pieces.append(text[start:index])
            index += len(separator)
            start = index
            continue
        index += 1
    pieces.append(text[start:])
    return pieces


def darwin_clause(text):
    text = text.strip()
    if not text:
        return True
    conjunctions = split_top(text, " and ")
    return all(
        any(darwin_alternative(item) for item in split_top(part, " or "))
        for part in conjunctions
    )


def darwin_applicable(availability):
    if not availability:
        return True
    clauses = re.findall(r"Available on (.+?) only", " ".join(availability))
    if not clauses:
        return True
    return all(darwin_clause(clause) for clause in clauses)


def load_records():
    records = []
    by_url = {}
    with gzip.open(SOURCE, "rt", encoding="utf-8") as stream:
        for line in stream:
            record = json.loads(line)
            records.append(record)
            by_url[record["url"]] = record
    return records, by_url


def classify(record, by_url, type_urls, trait_urls):
    if record.get("runtime_stability") != "stable" or record.get("deprecated"):
        return None
    path = record.get("rust_path") or ""
    if excluded_module(path):
        return None
    kind = record.get("kind")
    if kind in {"struct", "enum", "union", "primitive", "type"} and record["url"] in type_urls:
        folded = fold_path(path)
        return {
            "canonical_id": record["canonical_id"],
            "family": folded,
            "contract": record.get("contract") or record["url"],
            "mettle_path": mettle_path(path),
            "applicable": darwin_applicable(record.get("availability") or []),
        }
    if kind == "trait" and record["url"] in trait_urls:
        folded = fold_path(path)
        return {
            "canonical_id": record["canonical_id"],
            "family": folded,
            "contract": record.get("contract") or record["url"],
            "mettle_path": mettle_path(path),
            "applicable": darwin_applicable(record.get("availability") or []),
        }
    if kind == "fn" and record.get("parent") is None:
        parts = parts_of(path)
        if len(parts) >= 2 and (parts[-2], parts[-1]) in FREE_FUNCTIONS:
            return operation_row(record, path)
        return None
    if kind == "macro" and parts_of(path)[-1] in MACROS:
        return operation_row(record, path)
    if kind in INHERENT_KINDS and record.get("parent") in type_urls:
        context = by_url.get(record.get("context") or "")
        if context and context.get("kind") == "implementation" and context.get("implemented_interface"):
            return None
        return operation_row(record, path)
    if kind in TRAIT_MEMBER_KINDS and record.get("parent") in trait_urls:
        context = by_url.get(record.get("context") or "")
        if context and context.get("kind") == "implementation":
            return None
        return operation_row(record, path)
    if kind == "implementation":
        trait_url = record.get("implemented_interface")
        parent_url = record.get("parent")
        if trait_url not in trait_urls or parent_url not in type_urls:
            return None
        if self_type(record.get("signature") or "") is None:
            return None
        owner = fold_path(by_url[parent_url]["rust_path"])
        trait_name = fold_path(by_url[trait_url]["rust_path"]).split(".")[-1]
        family = owner + " implements " + trait_name
        return {
            "canonical_id": record["canonical_id"],
            "family": family,
            "contract": record.get("contract") or record["url"],
            "mettle_path": family,
            "applicable": darwin_applicable(record.get("availability") or []),
        }
    return None


def operation_row(record, path):
    return {
        "canonical_id": record["canonical_id"],
        "family": fold_path(path),
        "contract": record.get("contract") or record["url"],
        "mettle_path": mettle_path(path),
        "applicable": darwin_applicable(record.get("availability") or []),
    }


def previous_rows():
    if not OUTPUT.is_file():
        return {}
    saved = {}
    with OUTPUT.open(newline="", encoding="utf-8") as stream:
        for row in csv.DictReader(stream):
            saved[row["family"]] = (row["status"], row["evidence test"])
    return saved


def main():
    records, by_url = load_records()
    type_urls = set()
    trait_urls = set()
    for record in records:
        if record.get("runtime_stability") != "stable" or record.get("deprecated"):
            continue
        path = record.get("rust_path") or ""
        if excluded_module(path):
            continue
        if selected_type_name(path, record.get("kind")):
            type_urls.add(record["url"])
        if selected_trait_name(path, record.get("kind")):
            trait_urls.add(record["url"])

    families = {}
    for record in records:
        row = classify(record, by_url, type_urls, trait_urls)
        if row is None:
            continue
        current = families.get(row["family"])
        if current is None:
            families[row["family"]] = row
            continue
        current["applicable"] = current["applicable"] or row["applicable"]
        better_path = path_rank(row["mettle_path"]) < path_rank(current["mettle_path"])
        same_path = path_rank(row["mettle_path"]) == path_rank(current["mettle_path"])
        if better_path or (same_path and row["canonical_id"] < current["canonical_id"]):
            current["canonical_id"] = row["canonical_id"]
            current["contract"] = row["contract"]
            current["mettle_path"] = row["mettle_path"]

    saved = previous_rows()
    rows = []
    for family in sorted(families):
        item = families[family]
        if family in saved:
            status, evidence = saved[family]
        else:
            status, evidence = "missing", ""
        if not item["applicable"]:
            status, evidence = "not-applicable", ""
        elif status == "not-applicable":
            status = "missing"
        rows.append({
            "canonical_id": item["canonical_id"],
            "family": family,
            "Rust contract": item["contract"],
            "Mettle path": item["mettle_path"],
            "status": status,
            "evidence test": evidence,
        })
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=COLUMNS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    counts = {}
    for row in rows:
        counts[row["status"]] = counts.get(row["status"], 0) + 1
    print(f"wrote {len(rows)} families to {OUTPUT}")
    for status in sorted(counts):
        print(f"  {status}: {counts[status]}")


if __name__ == "__main__":
    main()
