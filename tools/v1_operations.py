#!/usr/bin/env python3
"""List frozen V1 operation candidates; preserve reviewed mappings and evidence.

The CSV is an implementation worklist, not a declaration or target-qualification
result. Unknown target conditions remain blocked instead of counting as passes.
"""

import argparse
import csv
import gzip
import hashlib
import io
import json
import re
from collections import Counter
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent.parent
BASELINE = ROOT / "docs" / "baseline"
COLUMNS = ("canonical_id", "family", "rust_contract", "mettle_path", "status",
           "evidence_test")
STATUSES = {"missing", "declared", "evidenced", "not-applicable", "blocked"}
WORKLIST_COLUMNS = (
    "canonical_id", "disposition", "milestone", "category", "kind",
    "rust_contract", "signature", "work_unit", "covered_by", "availability",
    "exposure_urls", "mettle_path", "recorded_v1_status", "evidence_test",
)
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


def worklist(records, previous):
    """Reconcile stable contracts without treating members as separate impls."""
    index = {record["url"]: record for record in records}
    groups = {}
    for record in records:
        if record["runtime_stability"] == "stable":
            groups.setdefault(record["canonical_id"], []).append(record)
    selected = {row["canonical_id"] for row in generate(records, previous)}
    if set(previous) != selected:
        raise ValueError("V1 ledger and selector differ; reconcile before reporting")
    shared = {}
    for identity, exposures in groups.items():
        retained = [item for item in exposures if not item["deprecated"]]
        keys = set()
        for item in retained:
            if (item["kind"] != "implementation" or not item["implemented_interface"]
                    or not item.get("source_file") or not item.get("source")
                    or not urlsplit(item["source"]).fragment):
                break
            interface = index.get(item["implemented_interface"])
            keys.add((item["source_file"], urlsplit(item["source"]).fragment,
                      item["signature"], interface["canonical_id"] if interface
                      else item["implemented_interface"]))
        else:
            if len(keys) == 1:
                shared.setdefault(next(iter(keys)), []).append(identity)
    work_units = {}
    for identities in shared.values():
        representative = min(identities, key=lambda identity: (identity not in selected, identity))
        work_units.update(dict.fromkeys(identities, representative))
    rows = []
    for identity, exposures in sorted(groups.items()):
        retained = [record for record in exposures if not record["deprecated"]]
        record = min(retained or exposures, key=lambda item: item["url"])
        dependencies = set()
        if not retained:
            disposition, milestone = "excluded-deprecated", ""
        elif identity in selected:
            disposition, milestone = "v1-obligation", "I13/I14"
        elif record["kind"] == "module":
            disposition, milestone = "namespace", ""
        elif all(item["kind"] == "implementation"
                 and item["implemented_interface"] is None for item in retained):
            disposition, milestone = "covered-by-owner", ""
            dependencies = {index[item["parent"]]["canonical_id"] for item in retained}
        elif all(item["interface_member"] and item["context"]
                 and index[item["context"]]["implemented_interface"]
                 for item in retained):
            disposition, milestone = "covered-by-implementation", ""
            dependencies = {index[item["context"]]["canonical_id"] for item in retained}
        else:
            disposition, milestone = "post-v1-obligation", "I17"
        if dependencies:
            for dependency in dependencies:
                if dependency not in groups or not any(
                        not item["deprecated"] for item in groups[dependency]):
                    raise ValueError(f"{identity}: uncovered dependency {dependency}")
            milestone = "I13/I14" if dependencies <= selected else "I17"
        paths = [item["rust_path"] for item in retained or exposures]
        if any("::arch::" in path for path in paths):
            category = "architecture"
        elif any("::os::" in path for path in paths):
            category = "os-extension"
        elif record["kind"] == "implementation":
            category = "trait-implementation"
        else:
            category = "library"
        old = previous.get(identity, {})
        rows.append({
            "canonical_id": identity, "disposition": disposition,
            "milestone": milestone, "category": category, "kind": record["kind"],
            "rust_contract": record["contract"], "signature": record["signature"],
            "work_unit": work_units.get(identity, identity),
            "covered_by": json.dumps(sorted(dependencies)),
            "availability": json.dumps(sorted({
                condition for item in retained or exposures
                for condition in item["availability"]})),
            "exposure_urls": json.dumps(sorted({item["url"] for item in exposures})),
            "mettle_path": old.get("mettle_path", ""),
            "recorded_v1_status": old.get("status", ""),
            "evidence_test": old.get("evidence_test", ""),
        })
    return rows


def worklist_summary(rows, records, manifest, ledger):
    obligations = [row for row in rows
                   if row["disposition"] == "post-v1-obligation"]
    units = {row["work_unit"] for row in obligations}
    v1_units = {row["work_unit"] for row in rows
                if row["disposition"] == "v1-obligation"}
    return {
        "manifest_sha256": hashlib.sha256(manifest.read_bytes()).hexdigest(),
        "v1_ledger_sha256": hashlib.sha256(ledger.read_bytes()).hexdigest(),
        "policy": {
            "deprecated": "excluded from required scope; reference retained",
            "platforms": "all reference profiles; source-cfg applicability unreviewed",
            "deduplication": "canonical identity; widths/signatures preserved",
            "work_units": "implementation source file/span, exact signature and trait identity",
            "implementation_members": "retained under their implementation obligation",
            "v1_membership": "existing selector, not target qualification",
        },
        "stable_exposures": sum(r["runtime_stability"] == "stable" for r in records),
        "stable_canonical_records": len(rows),
        "dispositions": dict(sorted(Counter(r["disposition"] for r in rows).items())),
        "post_v1_by_category": dict(sorted(Counter(
            r["category"] for r in obligations).items())),
        "post_v1_by_kind": dict(sorted(Counter(r["kind"] for r in obligations).items())),
        "post_v1_distinct_work_units": len(units),
        "post_v1_work_units_also_in_v1": len(units & v1_units),
        "post_v1_work_units_not_in_v1": len(units - v1_units),
        "work_unit_boundary": "shared implementation code, not shared type/profile evidence",
        "post_v1_implementation_status": "unreviewed, not assumed missing",
        "qualification": "no native declaration, execution or per-profile evidence inferred",
        "not_in_operation_inventory": [
            "I15 self-hosting", "I16 independent backend",
            "A009 Rust bridge capability", "profile bootstrap and qualification",
            "explicit native/supporting-protocol and experience-track obligations",
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=BASELINE / "operations.jsonl.gz")
    parser.add_argument("--output", type=Path, default=BASELINE / "v1-operations.csv")
    parser.add_argument("--remaining", action="store_true",
                        help="write the reconciled stable scope, not the V1 CSV")
    args = parser.parse_args()
    with gzip.open(args.manifest, "rt") as stream:
        records = [json.loads(line) for line in stream]
    previous = {}
    if args.output.exists():
        with args.output.open(newline="") as stream:
            previous = {row["canonical_id"]: row for row in csv.DictReader(stream)}
    if args.remaining:
        rows = worklist(records, previous)
        output = BASELINE / "post-v1-worklist.csv.gz"
        with output.open("wb") as raw:
            with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
                with io.TextIOWrapper(compressed, encoding="utf-8", newline="") as stream:
                    writer = csv.DictWriter(stream, fieldnames=WORKLIST_COLUMNS,
                                            lineterminator="\n")
                    writer.writeheader()
                    writer.writerows(rows)
        summary = worklist_summary(rows, records, args.manifest, args.output)
        (BASELINE / "post-v1-summary.json").write_text(
            json.dumps(summary, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(json.dumps(summary, indent=2, sort_keys=True))
        return
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
