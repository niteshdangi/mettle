#!/usr/bin/env python3
"""List frozen V1 operation candidates; preserve reviewed mappings and evidence.

The CSV is an implementation worklist, not a declaration or target-qualification
result. Unknown target conditions remain blocked instead of counting as passes.
"""

import argparse
import csv
import gzip
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "docs" / "baseline"
COLUMNS = ("canonical_id", "family", "rust_contract", "mettle_path", "status",
           "evidence_test")
STATUSES = {"missing", "declared", "evidenced", "not-applicable", "blocked"}
TYPE_KINDS = {"primitive", "struct", "enum", "type"}
MEMBER_KINDS = {"method", "tymethod", "associatedtype", "associatedconstant",
                "constant", "variant", "structfield"}

TYPES = {
    "primitive": """bool char str slice array tuple unit i8 i16 i32 i64 i128
                    isize u8 u16 u32 u64 u128 usize f32 f64""",
    "option": "Option",
    "result": "Result",
    "ops": "Range RangeInclusive",
    "mem": "ManuallyDrop",
    "ptr": "NonNull",
    "marker": "PhantomData",
    "cmp": "Reverse",
    "num": "Wrapping",
    "string": "String Drain",
    "vec": "Vec IntoIter Drain",
    "iter": """Map Filter Enumerate Zip Chain Rev Take Skip Peekable StepBy
              TakeWhile SkipWhile FlatMap Flatten Cloned Copied""",
    "slice": "Windows Chunks",
    "str": "Chars CharIndices Bytes Split SplitWhitespace",
    "boxed": "Box",
    "rc": "Rc Weak",
    "sync": """Arc Weak Mutex RwLock MutexGuard RwLockReadGuard RwLockWriteGuard
              Condvar Once OnceLock Barrier""",
    "cell": "Cell RefCell Ref RefMut OnceCell",
    "pin": "Pin",
    "sync::atomic": """AtomicBool AtomicPtr AtomicI32 AtomicU32 AtomicI64 AtomicU64
                      AtomicIsize AtomicUsize Ordering""",
    "sync::mpsc": "Sender SyncSender Receiver",
    "time": "Duration Instant SystemTime",
    "fmt": "Formatter Arguments",
    "io": """Error ErrorKind Stdin Stdout Stderr BufReader BufWriter Lines Cursor""",
    "fs": "File OpenOptions Metadata ReadDir DirEntry FileType Permissions",
    "path": "Path PathBuf",
    "ffi": "OsStr OsString CStr CString",
    "process": "Command Child Output ExitStatus Stdio",
    "net": "TcpListener TcpStream UdpSocket SocketAddr IpAddr Ipv4Addr Ipv6Addr",
    "thread": "JoinHandle Thread Scope ScopedJoinHandle",
    "task": "Poll Context Waker",
}
COLLECTIONS = {
    "binary_heap": "BinaryHeap Iter IntoIter Drain",
    "btree_map": "BTreeMap Entry Iter IterMut IntoIter Keys Values",
    "btree_set": "BTreeSet Iter IntoIter",
    "hash_map": "HashMap Entry Iter IterMut IntoIter Drain Keys Values",
    "hash_set": "HashSet Iter IntoIter Drain",
    "vec_deque": "VecDeque Iter IterMut IntoIter Drain",
}
TRAITS = {
    "iter": """Iterator IntoIterator DoubleEndedIterator ExactSizeIterator
              FromIterator Extend""",
    "clone": "Clone",
    "marker": "Copy Send Sync Sized",
    "default": "Default",
    "fmt": "Debug Display Write",
    "hash": "Hash Hasher BuildHasher",
    "cmp": "PartialEq Eq PartialOrd Ord",
    "io": "Write Read BufRead Seek",
    "convert": "From Into TryFrom TryInto AsRef AsMut",
    "borrow": "Borrow ToOwned",
    "string": "ToString",
    "str": "FromStr",
    "ops": """Add Sub Mul Div Rem BitAnd BitOr BitXor Shl Shr Neg Not AddAssign
             SubAssign MulAssign DivAssign RemAssign BitAndAssign BitOrAssign
             BitXorAssign ShlAssign ShrAssign Index IndexMut Deref DerefMut Drop
             Fn FnMut FnOnce""",
    "future": "Future",
    "error": "Error",
    "any": "Any",
}
FUNCTIONS = {
    "thread": "spawn scope sleep current yield_now available_parallelism",
    "fs": """read read_to_string write create_dir create_dir_all remove_file
             remove_dir remove_dir_all rename copy metadata read_dir canonicalize""",
    "env": "args var vars set_var remove_var current_dir set_current_dir temp_dir",
    "process": "exit abort id",
    "io": "stdin stdout stderr copy",
    "mem": "swap replace take drop forget size_of align_of size_of_val",
    "ptr": "null null_mut eq read write copy copy_nonoverlapping drop_in_place",
    "cmp": "min max",
    "iter": "once repeat empty from_fn successors zip",
    "sync::mpsc": "channel sync_channel",
    "hint": "black_box",
    "char": "from_u32 from_digit",
    "str": "from_utf8",
    "array": "from_fn",
}
MACROS = set("""print println eprint eprintln format format_args write writeln
                assert assert_eq assert_ne debug_assert debug_assert_eq
                debug_assert_ne panic vec unreachable todo unimplemented matches
                dbg""".split())


def paths(groups):
    return {f"{module}::{name}" for module, names in groups.items()
            for name in names.split()}


SELECTED_TYPES = paths(TYPES) | paths({
    f"collections::{module}": names for module, names in COLLECTIONS.items()
})
SELECTED_TRAITS = paths(TRAITS)
SELECTED_FUNCTIONS = paths(FUNCTIONS)


def public_path(record):
    return record["rust_path"].split("::", 1)[1]


def stable(record):
    return record["runtime_stability"] == "stable" and not record["deprecated"]


def target_status(record):
    """Evaluate the rendered conditions encountered in the selected worklist."""
    unknown = False
    for condition in record["availability"]:
        text = condition.removeprefix("Available on ").removesuffix(" only.")
        if text in {
            "Windows", "Linux", "WASI", "Android or Cygwin or Linux",
        }:
            return "not-applicable"
        if text in {
            "Unix", "Apple", "non-no_rc and non-no_sync",
            "Hermit or Motor OS or Trusty or Unix or WASI",
            "(Hermit or Motor OS or Trusty or Unix or WASI) and non-Trusty",
            "target_has_atomic=ptr and non-no_rc and non-no_sync",
        }:
            continue
        if re.fullmatch(r"target_has_atomic(?:_load_store)?=(?:8|32|64|ptr)", text):
            continue
        unknown = True
    return "blocked" if unknown else "missing"


def fold_widths(text):
    text = re.sub(r"\b(?:i|u)(?:8|16|32|64|128|size)\b", "integer", text)
    text = re.sub(r"\bf(?:32|64)\b", "float", text)
    return re.sub(r"\bAtomic(?:I|U)(?:32|64|size)\b", "AtomicInteger", text)


def family(record, pages):
    path = public_path(record)
    if record["kind"] == "implementation":
        owner = public_path(pages[record["parent"]])
        interface = public_path(pages[record["implemented_interface"]])
        # Every canonical substitution retains its own row and contract URL.
        # The family groups the nominal pair, not a proof of all substitutions.
        return "impl:" + fold_widths(f"{owner}:{interface}")
    return "operation:" + fold_widths(re.sub(r"-\d+$", "", path))


def implements_owner(record, owner):
    # Rustdoc also lists implementations on pages for their input types, e.g.
    # From<i32> for Wrapping<i32> on i32. Count them on the self-type page only.
    target = record["signature"].partition(" for ")[2].split("where", 1)[0].strip()
    target = re.sub(r"^&\s*(?:'\w+\s*)?(?:mut\s+)?", "", target)
    name = owner["rust_path"].rsplit("::", 1)[-1]
    if target.startswith("["):
        return name == ("array" if ";" in target else "slice")
    if target.startswith("("):
        return name == ("unit" if target == "()" else "tuple")
    match = re.match(r"(\w+)(?:::\w+)*", target)
    return bool(match and match[0].rsplit("::", 1)[-1] in {name, "T"})


def select(records):
    index = {record["url"]: record for record in records}
    pages = {record["url"]: record for record in records if record["parent"] is None}
    types = {url for url, record in pages.items()
             if stable(record) and record["kind"] in TYPE_KINDS
             and public_path(record) in SELECTED_TYPES}
    traits = {url for url, record in pages.items()
              if stable(record) and record["kind"] == "trait"
              and public_path(record) in SELECTED_TRAITS}
    declarations = types | traits
    selected = {}
    for record in records:
        if not stable(record):
            continue
        kind, parent = record["kind"], record["parent"]
        include = record["url"] in declarations
        if parent is None:
            include |= kind == "fn" and public_path(record) in SELECTED_FUNCTIONS
            include |= kind == "macro" and public_path(record) in MACROS
        elif kind == "implementation":
            include = (parent in types and record["implemented_interface"] in traits
                       and implements_owner(record, pages[parent]))
        elif kind in MEMBER_KINDS:
            context = index.get(record["context"], {})
            include = (parent in traits and record["context"] is None
                       or parent in types and record.get("interface_member") is None
                       and context.get("implemented_interface") is None)
        if include:
            selected.setdefault(record["canonical_id"], record)
    return [(record, family(record, pages)) for record in selected.values()]


def generate(records, previous):
    rows = []
    for record, group in select(records):
        identity = record["canonical_id"]
        old = previous.get(identity, {})
        status = old.get("status", target_status(record))
        if status not in STATUSES:
            raise ValueError(f"{identity}: unknown status {status!r}")
        if status == "evidenced" and not old.get("evidence_test"):
            raise ValueError(f"{identity}: evidenced operation requires a test")
        rows.append({
            "canonical_id": identity, "family": group,
            "rust_contract": record["contract"],
            "mettle_path": old.get("mettle_path", ""),
            "status": status, "evidence_test": old.get("evidence_test", ""),
        })
    return sorted(rows, key=lambda row: (row["family"], row["canonical_id"]))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=BASELINE / "operations.jsonl.gz")
    parser.add_argument("--output", type=Path, default=BASELINE / "v1-operations.csv")
    args = parser.parse_args()
    with gzip.open(args.manifest, "rt") as stream:
        records = [json.loads(line) for line in stream]
    previous = {}
    if args.output.exists():
        with args.output.open(newline="") as stream:
            previous = {row["canonical_id"]: row for row in csv.DictReader(stream)}
    rows = generate(records, previous)
    with args.output.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=COLUMNS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    families = {row["family"] for row in rows}
    print(f"{len(rows)} canonical records; "
          f"{sum(f.startswith('operation:') for f in families)} operation families; "
          f"{sum(f.startswith('impl:') for f in families)} implementation families")
    print(dict(Counter(row["status"] for row in rows)))


if __name__ == "__main__":
    main()
