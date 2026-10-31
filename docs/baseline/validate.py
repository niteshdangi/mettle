#!/usr/bin/env python3
"""Check the frozen documentation inventory, contexts and native rule assignments."""

import csv
import fnmatch
import gzip
import hashlib
import json
import os
import re
from collections import Counter
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).parent
BASE = "https://doc.rust-lang.org/1.99.1/"

def project_files(project, pattern):
    for directory, children, files in os.walk(project):
        children[:] = [name for name in children
                       if name not in {".git", ".tools", "build", "__pycache__"}]
        for name in files:
            if fnmatch.fnmatchcase(name, pattern):
                yield Path(directory) / name


def function_grammar_checks(productions, filename):
    failures = []
    compact = {name: re.sub(r"\s+", "", body) for name, body in productions.items()}

    def reject(problem):
        failures.append({"file": filename, "problem": problem})

    if any('"->"' in body for body in compact.values()):
        reject("Obsolete arrow result delimiter in native grammar")
    if compact.get("result_annotation") not in {'":",type_ref;', '":",simple_type;'}:
        reject("Function results must use a colon type annotation")
    for name in ("function", "closure"):
        if name in compact and "[result_annotation]" not in compact[name]:
            reject(f"{name} must permit body-based result inference")
    for name in ("callable_type", "foreign_declaration"):
        if name in compact and ("result_annotation" not in compact[name] or
                                "[result_annotation]" in compact[name]):
            reject(f"{name} must require an explicit result")
    if "unit_type" in compact or any(
            '"(",")"' in compact.get(name, "")
            for name in ("type_ref", "type_atom")):
        reject("Unit is a named type; empty parentheses are only a value")
    if "unit_value" in compact and compact["unit_value"] != '"(",")";':
        reject("The unit value must remain empty parentheses")
    if "unit_value" not in compact.get("primary", ""):
        reject("Expressions must retain the unit value")
    if '"never"' in compact.get("type_atom", ""):
        reject("Never is a predeclared type name, not a lowercase keyword")
    if filename == "core-grammar.md" and (
            "discard_binding" not in compact.get("binding", "") or
            compact.get("discard_binding") != '"let","_","=",expression;'):
        reject("Core explicit discard must require an initializer and create no named binding")
    return failures


def documentation_checks(project):
    failures = []
    documents = list(project_files(project, "*.md"))
    headings = {}
    for path in documents:
        text = path.read_text()
        if sum(line.startswith("```") for line in text.splitlines()) % 2:
            failures.append({"file": str(path.relative_to(project)), "problem": "Unclosed Markdown fence"})
        headings[path.resolve()] = {
            re.sub(r"[^\w -]", "", heading.strip().lower()).replace(" ", "-")
            for heading in re.findall(r"^#{1,6}\s+(.+)$", text, re.M)
        }

    def check_link(origin, target):
        if re.match(r"[a-zA-Z][\w+.-]*:", target):
            return
        filename, _, anchor = unquote(target).partition("#")
        path = (origin.parent / filename).resolve() if filename else origin.resolve()
        if not path.exists():
            failures.append({"file": str(origin.relative_to(project)), "problem": "Missing local link", "target": target})
        elif anchor and path in headings and anchor not in headings[path]:
            failures.append({"file": str(origin.relative_to(project)), "problem": "Missing heading anchor", "target": target})

    for path in documents:
        for target in re.findall(r"\[[^\]\n]+\]\(([^)\s]+)\)", path.read_text()):
            check_link(path, target)
    for family in json.loads((ROOT / "supporting-protocols.json").read_text())["families"]:
        check_link(ROOT / "supporting-protocols.json", family["contract"])
    capability_file = project / "docs/capabilities.csv"
    with capability_file.open() as stream:
        capabilities = list(csv.DictReader(stream))
    expected_ids = {f"{prefix}{i:03d}" for prefix, total in (("L", 60), ("S", 31), ("A", 9), ("T", 7))
                    for i in range(1, total + 1)}
    if len(capabilities) != 107 or {r["id"] for r in capabilities} != expected_ids:
        failures.append({"problem": "Capability identity/count mismatch"})
    for row in capabilities:
        if row["status"] != "specified" or row["implementation_status"] != "not_implemented":
            failures.append({"id": row["id"], "problem": "Unexpected specification/implementation status"})
        if not row["specification"] or not row["required_evidence"]:
            failures.append({"id": row["id"], "problem": "Missing owner/evidence obligation"})
        for target in row["specification"].split("|"):
            check_link(capability_file, target)
    milestone_text = (project / "docs/implementation-plan.md").read_text()
    milestone_rows = re.findall(
        r"^\| (I\d\d) \| ([^|\n]+) \| ([^|\n]+) \| ([^|\n]+) \|$",
        milestone_text, re.M)
    milestone_ids = {row[0] for row in milestone_rows}
    if len(milestone_rows) != 17 or milestone_ids != {f"I{i:02d}" for i in range(1, 18)}:
        failures.append({"problem": "Implementation milestone identity/count mismatch"})
    milestone_owners = {}
    for milestone, entries in re.findall(
            r"^\| (I\d\d) \| ([LSTA\d, -]+) \|$", milestone_text, re.M):
        for entry in entries.split(", "):
            match = re.fullmatch(r"([LSTA])(\d{3})(?:-([LSTA])(\d{3}))?", entry)
            if not match or (match[3] and match[1] != match[3]) or milestone not in milestone_ids:
                failures.append({"problem": "Invalid milestone capability range", "entry": entry})
                continue
            for number in range(int(match[2]), int(match[4] or match[2]) + 1):
                capability = f"{match[1]}{number:03d}"
                if capability in milestone_owners:
                    failures.append({"id": capability, "problem": "Multiple primary milestone owners"})
                milestone_owners[capability] = milestone
    if milestone_owners.keys() != expected_ids:
        failures.append({"problem": "Milestone capability coverage mismatch"})

    grammar, production_counts = {}, {}
    for filename in ("core-grammar.md", "language-grammar.md"):
        text = (project / "docs" / filename).read_text()
        body = "\n".join(re.findall(r"```ebnf\n(.*?)```", text, re.S))
        productions = re.findall(r"^([a-z_]\w*)\s*=\s*(.*?)(?=^[a-z_]\w*\s*=|\Z)", body, re.M | re.S)
        names = [name for name, _ in productions]
        if len(set(names)) != len(names):
            failures.append({"file": filename, "problem": "Duplicate grammar production"})
        failures.extend(function_grammar_checks(dict(productions), filename))
        grammar.update(productions)
        production_counts[filename] = len(productions)
    references = set()
    for body in grammar.values():
        body = re.sub(r'"[^"]*"', "", body)
        references.update(re.findall(r"\b[a-z_]\w*\b", body))
    if references - grammar.keys():
        failures.append({"problem": "Undefined grammar productions", "names": sorted(references - grammar.keys())})
    fixtures = set()
    for manifest in (project / "examples").rglob("expectations.json"):
        for case in json.loads(manifest.read_text())["cases"]:
            path = (manifest.parent / case["file"]).resolve()
            if path in fixtures or not path.is_file() or case["expect"] not in {"accept", "reject"}:
                failures.append({"file": case["file"], "problem": "Duplicate/invalid specification fixture"})
            fixtures.add(path)
    if fixtures != {p.resolve() for p in (project / "examples").rglob("*.mt")}:
        failures.append({"problem": "Fixture manifest membership mismatch"})
    for path in project_files(project, "*.json"):
        json.loads(path.read_text())
    for path in project_files(project, "*.py"):
        compile(path.read_text(), str(path), "exec")
    return {
        "markdown_files_checked": len(documents), "capabilities_checked": len(capabilities),
        "implementation_milestones_planned": len(milestone_rows),
        "milestone_capabilities_checked": len(milestone_owners),
        "grammar_productions": production_counts, "composed_grammar_productions": len(grammar),
        "function_result_and_unit_policies_checked": True,
        "fixture_expectations_checked": len(fixtures), "fixtures_executed": False,
    }, failures


def documentation_inputs(project):
    paths = (list(project_files(project, "*.md")) + list((project / "examples").rglob("*.mt")) +
             list((project / "examples").rglob("expectations.json")) +
             list(ROOT.glob("*.py")) +
             [project / "docs/capabilities.csv", project / "docs/toolchain-pins.json",
              ROOT / "sources.json", ROOT / "supporting-protocols.json"])
    hashes = {str(path.relative_to(project)): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in sorted(set(paths))}
    return hashes, hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()


def main():
    summary = json.loads((ROOT / "audit-summary.json").read_text())
    provenance = json.loads((ROOT / "source-provenance.json").read_text())
    failures = list(summary["failures"])
    redirects = {r["source_url"]: r["target_url"]
                 for r in csv.DictReader((ROOT / "redirects.csv").open())}
    index, selected = {}, {}
    counts = Counter()
    native_primitive_mappings = Counter()
    declared_rules = set(re.findall(
        r"\| (T\d\d) \|", (ROOT.parent / "library-surface.md").read_text()))
    expected_rules = {f"T{i:02d}" for i in range(1, 17)}
    if declared_rules != expected_rules:
        failures.append({"problem": "Translation rule definitions are incomplete"})

    def resolve(url):
        url, separator, fragment = url.partition("#")
        seen = set()
        while url in redirects and url not in seen:
            seen.add(url)
            url = redirects[url]
        return url + (separator + fragment if separator else "")

    with gzip.open(ROOT / "operations.jsonl.gz", "rt") as stream:
        for line in stream:
            record = json.loads(line)
            url = record["url"]
            if url in index:
                failures.append({"url": url, "problem": "Duplicate operation identity"})
            csv_record = {
                "source_url": url, "rust_path": record["rust_path"], "kind": record["kind"],
                "canonical_id": record["canonical_id"], "stability": record["runtime_stability"],
                "const_stability": record["const_stability"], "deprecated": str(record["deprecated"]).lower(),
                "definition_source": record["source"] or "", "native_mapping": record["native_operation"],
                "translation_rules": "|".join(record["translation_rules"]),
                "availability": json.dumps(record["availability"]), "parent_url": record["parent"] or "",
                "impl_context": record["context"] or "",
            }
            csv_digest = hashlib.sha256(json.dumps(csv_record, sort_keys=True).encode()).hexdigest()
            index[url] = (
                record["runtime_stability"], record["const_stability"],
                record["canonical_id"], record["parent"], record["context"],
                csv_digest,
            )
            counts[record["runtime_stability"]] += 1
            if not record["native_operation"] or not record["signature"]:
                failures.append({"url": url, "problem": "Missing native operation or reference declaration"})
            primitive = re.match(r"(?:core|std)::primitive::(unit|never)(?:::|$)", record["rust_path"])
            if primitive:
                name = primitive[1]
                native_primitive_mappings[name] += 1
                target = "core::" + {"unit": "Unit", "never": "Never"}[name]
                native = record["native_operation"]
                valid_native = (native == target if record["kind"] == "primitive"
                                else native.startswith(target + "::"))
                if not valid_native:
                    failures.append({"url": url, "problem": f"{target} native mapping uses obsolete type name"})
            if not set(record["translation_rules"]) <= declared_rules or "T01" not in record["translation_rules"]:
                failures.append({"url": url, "problem": "Unknown or missing translation rule"})
            if record["page_sha256"] != provenance["pages"].get(url.split("#")[0]):
                failures.append({"url": url, "problem": "Page provenance mismatch"})
            if record["runtime_stability"] == "stable":
                if record["const_stability"] in {"unresolved_const_contract", "nightly_runtime_const"}:
                    failures.append({"url": url, "problem": "Stable operation has unresolved const contract"})
                if not record["source"] and record["kind"] not in {
                        "primitive", "implementation", "variant", "structfield"}:
                    failures.append({"url": url, "problem": "Missing definition or derivation provenance"})
            if record["source_file"] and record["source_file"] not in provenance["source_files"]:
                failures.append({"url": url, "problem": "Missing source file hash"})
            if record["kind"] == "fn" and record["parent"] is None:
                name = url.rsplit("/", 1)[-1][3:-5]
                declaration_name = re.search(r"\bfn\s+(?:r#)?(\w+)", record["signature"])
                if not declaration_name or declaration_name[1] != name:
                    failures.append({"url": url, "problem": "Function spelling differs from archived path"})
            if any(key in url for key in (
                    "enum.Option.html", "struct.Vec.html", "method.provide",
                    "fn._mm_add_ps.html", "impl-Freeze-for-Vec",
                    "fn.Q6_p_and_pp.html", "fn.Q6_P_and_PP.html")):
                selected[url] = record

    missing_references = Counter()
    conditional_unstable_references = Counter()
    stable_canonical = {r[2] for r in index.values() if r[0] == "stable"}
    interface_relations = 0
    with gzip.open(ROOT / "operations.jsonl.gz", "rt") as stream:
        for line in stream:
            record = json.loads(line)
            for key in ("parent", "context", "implemented_interface", "interface_member"):
                dependency = record.get(key)
                if dependency and resolve(dependency) not in index:
                    failures.append({"url": record["url"], "problem": f"Missing {key}"})
            interface = record["implemented_interface"]
            if interface:
                interface_relations += 1
                dependency = index.get(resolve(interface))
                if record["runtime_stability"] == "stable" and dependency and dependency[0] == "unstable":
                    failures.append({"url": record["url"], "problem": "Stable implementation of unstable interface"})
            member = record["interface_member"]
            if member and record["runtime_stability"] == "stable":
                dependency = index.get(resolve(member))
                if dependency and dependency[0] == "unstable":
                    failures.append({"url": record["url"], "problem": "Stable implementation of unstable member"})
            for reference in record["declaration_references"]:
                target = resolve(reference["url"])
                target_page = target.split("#")[0]
                dependency = index.get(target) or index.get(target_page)
                if dependency is None and target.startswith(BASE):
                    missing_references[target] += 1
                elif (record["runtime_stability"] == "stable" and dependency and
                      dependency[0] == "unstable" and dependency[2] not in stable_canonical):
                    conditional_unstable_references[target_page] += 1
    for url, count in missing_references.items():
        failures.append({"url": url, "problem": "Unresolved declaration reference", "occurrences": count})
    protocols = json.loads((ROOT / "supporting-protocols.json").read_text())
    protocol_items = {}
    for family in protocols["families"]:
        for item in family["reference_items"]:
            if item in protocol_items:
                failures.append({"item": item, "problem": "Ambiguous supporting-protocol family"})
            protocol_items[item] = family["id"]
    supporting_families = Counter()
    for url, count in conditional_unstable_references.items():
        item = url.rsplit("/", 1)[-1].removesuffix(".html")
        if item not in protocol_items:
            failures.append({"url": url, "problem": "Unmapped conditional supporting protocol"})
        else:
            supporting_families[protocol_items[item]] += count

    checks = [
        ("alloc/vec/struct.Vec.html", "stable", "not_const_callable"),
        ("alloc/vec/struct.Vec.html#method.new", "stable", "stable"),
        ("alloc/vec/struct.Vec.html#method.with_capacity", "stable", "unstable"),
        ("core/arch/x86_64/fn._mm_add_ps.html", "stable", "unstable"),
        ("core/error/trait.Error.html#method.provide", "unstable", None),
        ("alloc/boxed/struct.Box.html#method.provide", "unstable", None),
        ("std/boxed/struct.Box.html#method.read_buf", "unstable", None),
        ("alloc/boxed/struct.Box.html#associatedtype.CallOnceFuture", "unstable", None),
        ("alloc/vec/struct.Vec.html#impl-Freeze-for-Vec%3CT,+A%3E", "unstable", None),
        ("core/arch/hexagon/scalar/fn.Q6_p_and_pp.html", "unstable", None),
        ("core/arch/hexagon/scalar/fn.Q6_P_and_PP.html", "unstable", None),
    ]
    for suffix, runtime, const in checks:
        actual = index.get(BASE + suffix)
        if actual is None or actual[0] != runtime or (const and actual[1] != const):
            failures.append({"url": BASE + suffix, "problem": "Stability/source-context regression", "actual": actual})
    for suffix in ("option/enum.Option.html", "pin/struct.Pin.html"):
        left, right = index.get(BASE + "core/" + suffix), index.get(BASE + "std/" + suffix)
        if left is None or right is None or left[2] != right[2]:
            failures.append({"problem": "Reexport lost canonical identity", "suffix": suffix})

    table_counts = {}
    for filename, expected in (
            ("public-items.csv", summary["public_pages"]),
            ("associated-items.csv", summary["associated_items"]),
            ("implementations.csv", summary["implementations"])):
        urls = set()
        rows = 0
        with (ROOT / filename).open() as stream:
            for row in csv.DictReader(stream):
                rows += 1
                urls.add(row["source_url"])
                record = index.get(row["source_url"])
                digest = hashlib.sha256(json.dumps(row, sort_keys=True).encode()).hexdigest()
                if record and digest != record[5]:
                    failures.append({"url": row["source_url"], "problem": "CSV/manifest contract mismatch"})
        table_counts[filename] = len(urls)
        if rows != expected or len(urls) != expected or not urls <= index.keys():
            failures.append({"problem": "CSV/manifest membership mismatch", "file": filename})
    if len(index) != sum(table_counts.values()):
        failures.append({"problem": "Operation totals differ"})
    documentation, documentation_failures = documentation_checks(ROOT.parent.parent)
    failures.extend(documentation_failures)
    document_inputs, document_digest = documentation_inputs(ROOT.parent.parent)
    source_constraints = 0
    with gzip.open(ROOT / "source-constraints.jsonl.gz", "rt") as stream:
        for line in stream:
            constraint = json.loads(line)
            source_constraints += 1
            expected = provenance["source_files"].get(constraint["file"])
            if expected and expected != constraint["sha256"]:
                failures.append({"file": constraint["file"], "problem": "Source-constraint provenance mismatch"})
    if source_constraints != summary["source_constraints_retained"]:
        failures.append({"problem": "Source-constraint count mismatch"})
    source_metadata = json.loads((ROOT / "sources.json").read_text())
    if source_metadata["source_commit"] != summary["source_commit"] or summary["source_commit"] != provenance["commit"]:
        failures.append({"problem": "Pinned source-identity mismatch"})
    for archive in source_metadata["archives"]:
        if archive["sha256"] != summary["archive_sha256"][archive["role"]]:
            failures.append({"problem": "Pinned archive-identity mismatch", "role": archive["role"]})
    result = {
        "status": "passed" if not failures else "failed",
        "operations_checked": len(index),
        "native_unit_mappings_checked": native_primitive_mappings["unit"],
        "native_never_mappings_checked": native_primitive_mappings["never"],
        "runtime_classification": dict(counts),
        "interface_relations_checked": interface_relations,
        "table_counts": table_counts,
        "known_edge_cases_checked": len(checks) + 2,
        "documentation_checks": documentation,
        "documentation_sha256": document_digest,
        "documentation_inputs": document_inputs,
        "source_constraints_checked": source_constraints,
        "conditional_unstable_declaration_references": dict(sorted(conditional_unstable_references.items())),
        "supporting_protocol_families": dict(sorted(supporting_families.items())),
        "failures": failures,
        "scope": "Documentation data, source identities, stability contexts, declaration-link closure and rule assignment; not compiler/soundness/runtime validation",
        "manifest_sha256": hashlib.sha256((ROOT / "operations.jsonl.gz").read_bytes()).hexdigest(),
    }
    (ROOT / "validation.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({
        k: v for k, v in result.items()
        if k not in {"conditional_unstable_declaration_references", "failures", "documentation_inputs"}
    }, indent=2))
    print(f"Conditional supporting contracts: {len(conditional_unstable_references)}")
    print(f"Failures: {len(failures)}")
    if failures:
        print(json.dumps(failures[:10], indent=2))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
