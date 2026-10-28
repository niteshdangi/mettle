#!/usr/bin/env python3
"""Reproduce the documentation inventory from verified Rust distribution inputs."""

import argparse
import bisect
import csv
import gzip
import hashlib
import html
import json
import re
import tarfile
from collections import Counter
from functools import lru_cache
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urljoin, urlsplit


BASE = "https://doc.rust-lang.org/1.99.1/"
COMMIT = "58cf8f9c35b355199727627d07ae34a4e2846d67"
CRATES = ("core", "alloc", "std")
ITEM_KINDS = {
    "fn", "struct", "enum", "trait", "union", "type", "constant", "static",
    "macro", "primitive", "attr", "derive", "traitalias", "attribute", "keyword",
}
TYPE_KINDS = {"struct", "enum", "trait", "union", "primitive", "type"}
MEMBER_PREFIXES = (
    "method.", "tymethod.", "associatedtype.", "associatedconstant.",
    "structfield.", "variant.",
)
VOID = {
    "area", "base", "br", "col", "embed", "hr", "img", "input",
    "link", "meta", "param", "source", "track", "wbr",
}


class Node:
    def __init__(self, tag, attrs=(), parent=None):
        self.tag, self.attrs, self.parent = tag, dict(attrs), parent
        self.children = []

    def walk(self):
        yield self
        for child in self.children:
            if isinstance(child, Node):
                yield from child.walk()

    def cls(self, name):
        return name in self.attrs.get("class", "").split()

    def text(self, declaration=False):
        if declaration and any(self.cls(c) for c in ("src", "since", "anchor", "hideme")):
            return ""
        return "".join(c.text(declaration) if isinstance(c, Node) else c
                       for c in self.children)


class Document(HTMLParser):
    def __init__(self, text):
        super().__init__(convert_charrefs=True)
        self.root = Node("root")
        self.current = self.root
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        node = Node(tag, attrs, self.current)
        self.current.children.append(node)
        if tag not in VOID:
            self.current = node

    def handle_endtag(self, tag):
        node = self.current
        while node.parent is not None:
            if node.tag == tag:
                self.current = node.parent
                return
            node = node.parent

    def handle_data(self, text):
        if self.current.tag not in {"script", "style"}:
            self.current.children.append(text)


def compact(text):
    return re.sub(r"\s+", " ", text).strip()


def signals(nodes):
    result = {"unstable": False, "deprecated": False, "since": [], "availability": []}
    for node in nodes:
        if node.cls("stab"):
            result["unstable"] |= node.cls("unstable")
            result["deprecated"] |= node.cls("deprecated")
            if node.cls("portability"):
                result["availability"].append(compact(node.text()))
        if node.cls("since"):
            result["since"].append(node.attrs.get("title", compact(node.text())))
    return result


def summary_nodes(node):
    if node.parent and node.parent.tag == "summary":
        return list(node.parent.walk())
    return list(node.walk())


def source_link(nodes, url):
    for node in nodes:
        if node.tag == "a" and node.cls("src"):
            target = urljoin(url, node.attrs["href"])
            if "/src/" in target:
                return target
    return None


def header(nodes):
    for node in nodes:
        if node.cls("code-header") or node.cls("item-decl"):
            return compact(node.text(declaration=True))
    return ""


def declaration_links(nodes, url):
    result = []
    for node in nodes:
        if node.tag == "a" and node.attrs.get("href") and any(
                node.cls(c) for c in ("trait", "struct", "enum", "union", "type",
                                      "primitive", "associatedtype")):
            target = urljoin(url, node.attrs["href"])
            result.append({
                "url": target, "name": node.text(),
                "kind": next(c for c in ("trait", "struct", "enum", "union", "type",
                                         "primitive", "associatedtype") if node.cls(c)),
            })
    return list({r["url"]: r for r in result}.values())


def trait_body_start(signature):
    angles = parentheses = brackets = 0
    for position, char in enumerate(signature):
        if char == "{" and angles == parentheses == brackets == 0:
            return position
        angles += (char == "<") - (char == ">" and signature[position - 1] != "-")
        parentheses += (char == "(") - (char == ")")
        brackets += (char == "[") - (char == "]")
    return len(signature)


def declaration_header_nodes(node, trait=False):
    remaining = trait_body_start(node.text(declaration=True)) if trait else None

    def visit(current):
        nonlocal remaining
        if remaining is not None and remaining <= 0:
            return
        if any(current.cls(c) for c in ("src", "since", "anchor", "hideme")):
            return
        yield current
        for child in current.children:
            if isinstance(child, Node):
                yield from visit(child)
            elif remaining is not None:
                remaining -= len(child)

    yield from visit(node)


def trait_header(signature):
    return signature[:trait_body_start(signature)].rstrip() + " { /* associated items specified separately */ }"


def implemented_interface(signature, links):
    if not signature.startswith("impl"):
        return None
    position = 4
    while position < len(signature) and signature[position].isspace():
        position += 1
    if position < len(signature) and signature[position] == "<":
        depth = 1
        position += 1
        while position < len(signature) and depth:
            depth += ((signature[position] == "<") -
                      (signature[position] == ">" and signature[position - 1] != "-"))
            position += 1
    tail = signature[position:].strip()
    if " for " not in tail:
        return None
    tail = re.sub(r"^(?:const\s+|!\s*)", "", tail)
    name = re.match(r"[\w:]+", tail)
    if not name:
        return None
    label = name[0].rsplit("::", 1)[-1]
    return next((r["url"] for r in links
                 if r["name"] == label and "/trait." in r["url"]), None)


def source_path(url, source_root):
    if not url:
        return None
    relative = unquote(urlsplit(url).path.split("/src/", 1)[1])
    relative = relative.removesuffix(".html") if hasattr(str, "removesuffix") else relative[:-5]
    crate, _, tail = relative.partition("/")
    if tail.startswith(("stdarch/", "portable-simd/")):
        path = source_root / tail
    elif crate == "std" and tail.startswith("core/src/"):
        path = source_root / tail
    else:
        path = source_root / crate / "src" / tail
    return path if path.is_file() else None


def versioned_modules(url):
    parts = urlsplit(url).path.split("/")[2:]
    return [BASE + "/".join(parts[:n]) + "/index.html"
            for n in range(1, len(parts))]


def write_csv(path, rows, fields):
    with path.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def feature_rules(record):
    signature, path = record["signature"], record["rust_path"]
    rules = {"T01"}
    tests = {
        "T02": r"&|'[a-zA-Z_]|\bfrom\b",
        "T03": r"\b(?:Box|Arc|Rc|Weak|Pin)\b",
        "T04": r"\b(?:Option|Result)\b",
        "T05": r"\b(?:Fn|FnMut|FnOnce)\b|\bfn\b",
        "T06": r"\b(?:dyn|impl)\b",
        "T07": r"\bfor\s*<",
        "T08": r"\bconst\b",
        "T09": r"\bunsafe\b|\*(?:const|mut)\b",
        "T10": r"\bextern\b|\bVaList",
        "T11": r"\b(?:Send|Sync|Unpin|UnwindSafe|RefUnwindSafe|Sized)\b",
        "T12": r"\b(?:Self|Iterator|IntoIterator|Output)\b|::",
        "T13": r"\?Sized|\[[^\];]+\]|\bstr\b",
    }
    for rule, pattern in tests.items():
        if re.search(pattern, signature):
            rules.add(rule)
    if "::arch::" in path or "::simd::" in path:
        rules.add("T14")
    if record["kind"] in {"macro", "attr", "derive", "attribute", "keyword"}:
        rules.add("T15")
    if record["kind"] == "implementation":
        rules.add("T16")
    return sorted(rules)


def native_path(record):
    path = record["rust_path"]
    if record["kind"] in {"method", "tymethod", "associatedtype", "associatedconstant"}:
        path = re.sub(r"-\d+$", "", path)
    if record["kind"] == "primitive":
        name = path.split("::")[-1]
        if name == "unit":
            return "core::Unit"
        if name == "never":
            return "core::Never"
        return "core::Text" if name == "str" else "core::" + name
    replacements = {
        "core::primitive::unit": "core::Unit",
        "std::primitive::unit": "core::Unit",
        "core::primitive::never": "core::Never",
        "std::primitive::never": "core::Never",
        "core::primitive::str": "core::Text",
        "std::primitive::str": "core::Text",
        "alloc::boxed::Box": "heap",
        "std::boxed::Box": "heap",
        "alloc::sync::Arc": "shared",
        "std::sync::Arc": "shared",
        "alloc::rc::Rc": "local shared",
        "std::rc::Rc": "local shared",
        "alloc::sync::Weak": "weak",
        "std::sync::Weak": "weak",
        "alloc::rc::Weak": "local weak",
        "std::rc::Weak": "local weak",
        "core::pin::Pin": "pinned",
        "std::pin::Pin": "pinned",
        "core::option::Option": "native_optional",
        "std::option::Option": "native_optional",
        "core::result::Result": "native_outcome",
        "std::result::Result": "native_outcome",
        "core::marker::Send": "Transferable",
        "std::marker::Send": "Transferable",
        "core::marker::Sync": "Shareable",
        "std::marker::Sync": "Shareable",
    }
    for old, new in replacements.items():
        if path == old or path.startswith(old + "::"):
            mapped = new + path[len(old):]
            if new in {"shared", "local shared", "weak", "local weak"}:
                mapped = re.sub(r"::clone$", "::retain", mapped)
            return mapped
    return path


def source_attributes(text):
    special = re.compile(r'//|/\*|(?:br|r)#{0,255}"|b?"|b?\'(?:\\.|[^\'\\\n])\'|#\s*!?\[')
    newline_offsets = [m.start() for m in re.finditer("\n", text)]

    def skip(match):
        token = match[0]
        if token == "//":
            end = text.find("\n", match.end())
            return len(text) if end == -1 else end + 1
        if token == "/*":
            depth, position = 1, match.end()
            while depth:
                nested = re.search(r"/\*|\*/", text[position:])
                if nested is None:
                    return len(text)
                depth += 1 if nested[0] == "/*" else -1
                position += nested.end()
            return position
        if token.startswith(("r", "br")):
            fence = '"' + "#" * token.count("#")
            end = text.find(fence, match.end())
            return len(text) if end == -1 else end + len(fence)
        if token.endswith("'"):
            return match.end()
        position = match.end()
        while position < len(text):
            if text[position] == "\\":
                position += 2
            elif text[position] == '"':
                return position + 1
            else:
                position += 1
        return len(text)

    position = 0
    while True:
        match = special.search(text, position)
        if match is None:
            return
        if not match[0].startswith("#"):
            position = skip(match)
            continue
        start, position, depth = match.start(), match.end(), 1
        while position < len(text) and depth:
            nested = special.match(text, position)
            if nested and not nested[0].startswith("#"):
                position = skip(nested)
            else:
                depth += (text[position] == "[") - (text[position] == "]")
                position += 1
        body = text[match.end():position - 1]
        name = re.match(r"\s*([a-zA-Z_]\w*)", body)
        if name:
            yield {
                "name": name[1], "text": text[start:position],
                "line": bisect.bisect_left(newline_offsets, start) + 1,
                "offset": start, "end": position,
                "inner": "!" in match[0],
            }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--docs-root", required=True, type=Path)
    parser.add_argument("--source-root", required=True, type=Path)
    parser.add_argument("--docs-archive", required=True, type=Path)
    parser.add_argument("--source-archive", required=True, type=Path)
    parser.add_argument("--output", type=Path, default=Path(__file__).parent)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    pages, redirects, failures = {}, {}, []
    archive_hashes = {
        "docs": "f94e0e39c45d4517981d35cd695eef30aeead92a5875f1014cd851fda1b2321e",
        "source": "e485a88c45db546b73571df7bebfcb4454ba4fb552c492e25fc5b00eeb5bf22d",
    }
    for role, file in (("docs", args.docs_archive), ("source", args.source_archive)):
        if hashlib.sha256(file.read_bytes()).hexdigest() != archive_hashes[role]:
            raise SystemExit(f"Unexpected {role} archive checksum")
    archived_sources = {}
    with tarfile.open(args.source_archive, "r:xz") as archive:
        prefix = "rust-src-1.99.1/rust-src/lib/rustlib/src/rust/library/"
        for member in archive:
            if member.isfile() and member.name.startswith(prefix) and member.name.endswith(".rs"):
                archived_sources[member.name[len(prefix):]] = hashlib.sha256(
                    archive.extractfile(member).read()).hexdigest()
    exact_files = {}
    case_overrides = 0
    with tarfile.open(args.docs_archive, "r:xz") as archive:
        prefix = "rust-docs-1.99.1-x86_64-unknown-linux-gnu/rust-docs/share/doc/rust/html/"
        cache = args.docs_root.parent / "rust-doc-exact-overrides"
        for member in archive:
            if not member.isfile() or not member.name.startswith(prefix):
                continue
            relative = member.name[len(prefix):]
            if relative.split("/", 1)[0] not in CRATES or not relative.endswith(".html"):
                continue
            data = archive.extractfile(member).read()
            file = args.docs_root / relative
            if not file.is_file() or file.read_bytes() != data:
                cache.mkdir(exist_ok=True)
                file = cache / (hashlib.sha256(relative.encode()).hexdigest() + ".html")
                file.write_bytes(data)
                case_overrides += 1
            exact_files[relative] = file
    catalog_urls = set()
    for crate in CRATES:
        catalog = Document((args.docs_root / crate / "all.html").read_text())
        for node in catalog.root.walk():
            if node.tag == "a":
                target = urljoin(BASE + crate + "/all.html", node.attrs.get("href", ""))
                if re.search(r"/(?:struct|enum|trait|fn|type|union|constant|static|macro|primitive|attr|derive|traitalias)\.[^/]+\.html$", target):
                    catalog_urls.add(target)
    for relative, file in sorted(exact_files.items()):
        name = relative.rsplit("/", 1)[-1]
        kind = "module" if name == "index.html" else name.split(".", 1)[0]
        if kind not in ITEM_KINDS | {"module"}:
            continue
        text = file.read_text()
        url = BASE + relative
        redirect = re.search(r'http-equiv="refresh" content="0;URL=([^"]+)"', text[:1000])
        if redirect:
            redirects[url] = urljoin(url, html.unescape(redirect[1]))
            continue
        version = re.search(r'data-rustdoc-version="([^"]+)"', text[:10000])
        if not version or not version[1].startswith("1.99.1 (58cf8f9c3 "):
            failures.append({"url": url, "problem": "Unexpected or absent rustdoc identity"})
            continue
        pages[url] = {"file": file, "kind": kind, "sha256": hashlib.sha256(text.encode()).hexdigest()}
    print(f"Indexed {len(pages)} pages and {len(redirects)} redirects", flush=True)
    for url in sorted(catalog_urls - pages.keys() - redirects.keys()):
        failures.append({"url": url, "problem": "Catalog entry absent from the archived public pages"})

    records, module_signals = [], {}
    source_files = {}
    for index, (url, page) in enumerate(sorted(pages.items())):
        kind = page["kind"]
        text = page["file"].read_text()
        start = text.index("<main")
        if kind not in TYPE_KINDS | {"module"}:
            stop = text.find('<details class="toggle top-doc"', start)
            if stop == -1:
                stop = text.find("<h2", start)
            text = text[start:stop] if stop != -1 else text[start:]
        else:
            text = text[start:]
        doc = Document(text)
        nodes = list(doc.root.walk())
        heading = next((n for n in nodes if n.cls("main-heading")), None)
        if heading is None:
            failures.append({"url": url, "problem": "Missing main heading"})
            continue
        top_nodes = list(heading.walk())
        content = heading.parent
        for child in content.children:
            if isinstance(child, Node) and child.cls("item-info"):
                top_nodes.extend(child.walk())
        own = signals(top_nodes)
        if kind == "module":
            module_signals[url] = own
        path_parts = urlsplit(url).path.split("/")[2:]
        item_name = path_parts[-1].split(".", 1)[1][:-5] if kind != "module" else ""
        rust_path = "::".join(path_parts[:-1] + ([item_name] if item_name else []))
        if kind == "primitive":
            rust_path = path_parts[0] + "::primitive::" + item_name
        source = source_link(top_nodes, url)
        signature = header(nodes)
        declaration = next((n for n in nodes if n.cls("item-decl")), heading)
        if kind == "trait":
            signature = trait_header(signature)
        if not signature:
            signature = compact(heading.text(declaration=True))
        root_record = {
            "url": url, "kind": kind, "rust_path": rust_path,
            "signature": signature, "source": source, "own": own,
            "parent": None, "context": None, "page_sha256": page["sha256"],
            "declaration_references": declaration_links(
                declaration_header_nodes(declaration, trait=kind == "trait"), url),
            "implemented_interface": None,
        }
        records.append(root_record)
        if kind in TYPE_KINDS:
            seen = set()
            for node in nodes:
                anchor = node.attrs.get("id", "")
                is_impl = node.cls("impl") and anchor.startswith("impl")
                if not is_impl and not anchor.startswith(MEMBER_PREFIXES):
                    continue
                if anchor in seen:
                    continue
                seen.add(anchor)
                metadata = summary_nodes(node)
                context = None
                ancestor = node.parent
                while ancestor is not None:
                    if ancestor.cls("implementors-toggle"):
                        summary = next((c for c in ancestor.children
                                        if isinstance(c, Node) and c.tag == "summary"), None)
                        if summary:
                            impl_node = next((n for n in summary.walk() if n.cls("impl")), None)
                            if impl_node and impl_node is not node:
                                context = url + "#" + impl_node.attrs["id"]
                        break
                    ancestor = ancestor.parent
                member_kind = "implementation" if is_impl else anchor.split(".", 1)[0]
                member_name = unquote(anchor.split(".", 1)[-1])
                member_signature = header(metadata)
                if not member_signature:
                    member_signature = compact(node.text(declaration=True))
                links = declaration_links(metadata, url)
                records.append({
                    "url": url + "#" + anchor, "kind": member_kind,
                    "rust_path": rust_path + "::" + member_name,
                    "signature": member_signature,
                    "source": source_link(metadata, url),
                    "own": signals(metadata), "parent": url, "context": context,
                    "page_sha256": page["sha256"],
                    "declaration_references": links,
                    "implemented_interface": (
                        implemented_interface(member_signature, links) if is_impl else None),
                })
        if (index + 1) % 4000 == 0:
            print(f"Parsed {index + 1}/{len(pages)} pages", flush=True)

    by_url = {r["url"]: r for r in records}
    if len(by_url) != len(records):
        failures.append({"problem": "Duplicate operation URLs"})
    source_spans = {}
    for record in records:
        source = record["source"]
        if not source or source in source_spans:
            continue
        if urlsplit(source).netloc != "doc.rust-lang.org":
            continue
        file = source_path(source, args.source_root)
        if file:
            relative = file.relative_to(args.source_root).as_posix()
            if relative not in source_files:
                source_files[relative] = hashlib.sha256(file.read_bytes()).hexdigest()
            source_spans[source] = relative
        else:
            failures.append({"url": record["url"], "source": source,
                             "problem": "Source link absent from source distribution"})

    source_metadata = {}
    retained_attributes = {
        "cfg", "cfg_attr", "target_feature", "stable", "unstable",
        "rustc_const_stable", "rustc_const_unstable", "deprecated", "repr",
    }
    constraints_count = 0
    verified_source_paths = set()
    with (args.output / "source-constraints.jsonl.gz").open("wb") as stream:
        with gzip.GzipFile(filename="", mode="wb", fileobj=stream, mtime=0) as compressed:
            for file in sorted(args.source_root.rglob("*.rs")):
                relative = file.relative_to(args.source_root).as_posix()
                text = file.read_text()
                digest = hashlib.sha256(text.encode()).hexdigest()
                if archived_sources.get(relative) != digest:
                    failures.append({"file": relative, "problem": "Source file differs from verified archive"})
                verified_source_paths.add(relative)
                attrs = list(source_attributes(text))
                if relative in source_files:
                    source_metadata[relative] = (
                        text, attrs, [a["end"] for a in attrs],
                        [0] + [m.end() for m in re.finditer("\n", text)])
                for attr in attrs:
                    if attr["name"] in retained_attributes:
                        compressed.write((json.dumps({
                            "file": relative, "sha256": digest, **attr,
                        }, sort_keys=True) + "\n").encode())
                        constraints_count += 1
    for relative in sorted(archived_sources.keys() - verified_source_paths):
        failures.append({"file": relative, "problem": "Archived source file absent from source tree"})

    @lru_cache(maxsize=None)
    def direct_attributes(file, source):
        if not file:
            return []
        text, attrs, ends, offsets = source_metadata[file]
        span = urlsplit(source).fragment
        first = re.match(r"\d+", span)
        if not first:
            return []
        line = int(first[0])
        offset = offsets[line - 1]
        while offset < len(text) and text[offset] in " \t":
            offset += 1
        index = bisect.bisect_right(ends, offset) - 1
        result = []
        while index >= 0:
            attr = attrs[index]
            gap = text[attr["end"]:offset]
            gap = re.sub(r"//[^\n]*|/\*.*?\*/", "", gap, flags=re.S)
            if gap.strip():
                break
            result.append({"name": attr["name"], "text": attr["text"], "line": attr["line"]})
            offset, index = attr["offset"], index - 1
        return list(reversed(result))

    stable_aliases = {}

    def resolve_record(url):
        page, separator, fragment = url.partition("#")
        seen = set()
        while page in redirects and page not in seen:
            seen.add(page)
            page = redirects[page]
        if fragment == "trait-implementations-1" and page.endswith("/primitive.tuple.html"):
            return by_url.get(page)
        return by_url.get(page + (separator + fragment if separator else ""))

    def interface_member(record, visiting):
        if not record["context"] or record["kind"] not in {
                "method", "tymethod", "associatedtype", "associatedconstant"}:
            return None
        context = by_url[record["context"]]
        classify(context, visiting)
        interface = context["implemented_interface"]
        if not interface or not interface.startswith(BASE):
            return None
        declaration = resolve_record(interface)
        if declaration is None:
            return None
        classify(declaration, visiting)
        declaration = by_url[stable_aliases.get(declaration["canonical_id"], declaration["url"])]
        name = re.sub(r"-\d+$", "", record["url"].rsplit("#", 1)[-1].split(".", 1)[-1])
        prefixes = (("method", "tymethod") if record["kind"] in {"method", "tymethod"}
                    else (record["kind"],))
        for prefix in prefixes:
            target = declaration["url"] + "#" + prefix + "." + name
            if target in by_url:
                return target
        failures.append({"url": record["url"], "interface": declaration["url"],
                         "problem": "Implementation member has no interface declaration"})
        return None

    def classify(record, visiting=None):
        if "runtime_stability" in record:
            return
        visiting = set() if visiting is None else visiting
        if record["url"] in visiting:
            failures.append({"url": record["url"], "problem": "Context cycle"})
            return
        visiting.add(record["url"])
        record["source_file"] = source_spans.get(record["source"])
        record["direct_source_attributes"] = direct_attributes(record["source_file"], record["source"])
        direct_names = {a["name"] for a in record["direct_source_attributes"]}
        if "unstable" in direct_names:
            record["own"]["unstable"] = True
        if "deprecated" in direct_names:
            record["own"]["deprecated"] = True
        evidence = [(record["url"], record["own"])]
        dependencies = [record["parent"], record["context"], record["implemented_interface"]]
        record["interface_member"] = interface_member(record, visiting)
        dependencies.append(record["interface_member"])
        if not record["parent"]:
            dependencies.extend(ancestor for ancestor in versioned_modules(record["url"])
                                if ancestor != record["url"] and ancestor in by_url)
        if record["kind"] == "implementation":
            dependencies.extend(r["url"] for r in record["declaration_references"]
                                if r["kind"] in {"struct", "enum", "union", "type", "primitive"})
        for dependency in dependencies:
            if dependency:
                if not dependency.startswith(BASE):
                    continue
                parent = resolve_record(dependency)
                if parent is None:
                    failures.append({"url": record["url"], "dependency": dependency,
                                     "problem": "Declaration dependency is not in the baseline"})
                    continue
                classify(parent, visiting)
                if (record["kind"] == "implementation" and
                        parent["kind"] in {"struct", "enum", "union", "type", "primitive"}):
                    alias = stable_aliases.get(parent["canonical_id"])
                    if alias:
                        parent = by_url[alias]
                evidence.extend(parent["stability_evidence"])
        evidence = list({url: signal for url, signal in evidence}.items())
        unstable = any(s["unstable"] for _, s in evidence)
        stable_since = any(re.search(r"Stable since Rust version \d", x)
                           for _, s in evidence for x in s["since"])
        external = bool(record["source"] and
                        urlsplit(record["source"]).netloc != "doc.rust-lang.org")
        external |= any(by_url[p].get("runtime_stability") == "external_implementation"
                        for p in (record["parent"], record["context"]) if p)
        if record["kind"] in {"keyword", "attribute"}:
            record["runtime_stability"] = "language_documentation"
        elif external:
            record["runtime_stability"] = "external_implementation"
        else:
            record["runtime_stability"] = "unstable" if unstable else (
                "stable" if stable_since else "unresolved")
        if record["runtime_stability"] == "unresolved":
            failures.append({"url": record["url"], "problem": "No positive stability context"})
        hints = record["own"]["since"]
        if "rustc_const_unstable" in direct_names or any("const unstable" in h for h in hints):
            const = "unstable"
        elif "rustc_const_stable" in direct_names or any("const since" in h for h in hints):
            const = "stable"
        elif re.search(r"\bconst\s+(?:unsafe\s+)?fn\b", record["signature"]):
            const = ("nightly_runtime_const" if record["runtime_stability"] == "unstable"
                     else "unresolved_const_contract")
        else:
            const = "not_const_callable"
        record["const_stability"] = const
        record["deprecated"] = any(s["deprecated"] for _, s in evidence)
        record["stability_evidence"] = evidence
        record["availability"] = list(dict.fromkeys(
            p for _, s in evidence for p in s["availability"]))
        if record["source"]:
            origin = (record["source_file"] + "#" + urlsplit(record["source"]).fragment.split("-")[0]
                      if record["source_file"] else record["source"])
            identity = origin + "|" + record["kind"] + "|" + record["signature"]
        elif record["parent"]:
            identity = by_url[record["parent"]]["canonical_id"] + "|" + record["kind"] + "|" + record["signature"]
        elif record["kind"] == "primitive":
            identity = "builtin:primitive:" + record["rust_path"].split("::")[-1]
        else:
            identity = "builtin-or-documentation:" + record["rust_path"]
        if record["parent"] and record["source"]:
            identity += "|" + by_url[record["parent"]]["canonical_id"]
        if record["context"]:
            identity += "|" + by_url[record["context"]]["canonical_id"]
        record["canonical_id"] = "B" + hashlib.sha256(identity.encode()).hexdigest()[:24]
        record["native_operation"] = native_path(record)
        record["translation_rules"] = feature_rules(record)
        record["requirement"] = {
            "stable": "required_when_applicable",
            "unstable": "not_automatic_stable_baseline",
            "language_documentation": "native_language_facility_mapping",
            "external_implementation": "outside_core_alloc_std_public_type_surface",
        }.get(record["runtime_stability"], "unresolved")
        record["contract"] = record["url"]
        visiting.remove(record["url"])

    for record in records:
        if record["parent"] is None:
            classify(record)
    stable_aliases = {r["canonical_id"]: r["url"] for r in records
                      if r["parent"] is None and r["runtime_stability"] == "stable"}
    for record in records:
        classify(record)

    for url in sorted(catalog_urls & redirects.keys()):
        target = redirects[url]
        visited = {url}
        while target in redirects and target not in visited:
            visited.add(target)
            target = redirects[target]
        if target not in by_url:
            failures.append({"url": url, "problem": "Catalog redirect target unresolved"})
            continue
        record = dict(by_url[target])
        parts = urlsplit(url).path.split("/")[2:]
        record["url"], record["rust_path"] = url, "::".join(
            parts[:-1] + [parts[-1].split(".", 1)[1][:-5]])
        record["redirect_target"] = target
        record["contract"] = target
        record["native_operation"] = native_path(record)
        records.append(record)

    public = [r for r in records if r["parent"] is None]
    members = [r for r in records if r["parent"] and r["kind"] != "implementation"]
    implementations = [r for r in records if r["kind"] == "implementation"]
    csv_fields = [
        "source_url", "rust_path", "kind", "canonical_id", "stability",
        "const_stability", "deprecated", "definition_source", "native_mapping",
        "translation_rules", "availability", "parent_url", "impl_context",
    ]

    def csv_row(record):
        return {
            "source_url": record["url"], "rust_path": record["rust_path"],
            "kind": record["kind"], "canonical_id": record["canonical_id"],
            "stability": record["runtime_stability"],
            "const_stability": record["const_stability"],
            "deprecated": str(record["deprecated"]).lower(),
            "definition_source": record["source"] or "",
            "native_mapping": record["native_operation"],
            "translation_rules": "|".join(record["translation_rules"]),
            "availability": json.dumps(record["availability"]),
            "parent_url": record["parent"] or "",
            "impl_context": record["context"] or "",
        }

    write_csv(args.output / "public-items.csv", map(csv_row, public), csv_fields)
    write_csv(args.output / "associated-items.csv", map(csv_row, members), csv_fields)
    write_csv(args.output / "implementations.csv", map(csv_row, implementations), csv_fields)
    write_csv(args.output / "redirects.csv",
              ({"source_url": a, "target_url": b} for a, b in sorted(redirects.items())),
              ["source_url", "target_url"])
    with (args.output / "operations.jsonl.gz").open("wb") as stream:
        with gzip.GzipFile(filename="", mode="wb", fileobj=stream, mtime=0) as compressed:
            for record in sorted(records, key=lambda r: r["url"]):
                compressed.write((json.dumps(record, sort_keys=True) + "\n").encode())
    provenance = {
        "commit": COMMIT, "source_files": source_files,
        "pages": {url: p["sha256"] for url, p in sorted(pages.items())},
    }
    (args.output / "source-provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    summary = {
        "baseline": "Rust 1.99.1", "source_commit": COMMIT,
        "public_pages": len(public), "associated_items": len(members),
        "implementations": len(implementations), "redirects": len(redirects),
        "canonical_contracts": len({r["canonical_id"] for r in records}),
        "canonical_required_contracts": len({
            r["canonical_id"] for r in records if r["runtime_stability"] == "stable"}),
        "public_stability": dict(Counter(r["runtime_stability"] for r in public)),
        "associated_stability": dict(Counter(r["runtime_stability"] for r in members)),
        "implementation_stability": dict(Counter(r["runtime_stability"] for r in implementations)),
        "const_stability": dict(Counter(r["const_stability"] for r in records)),
        "source_files_verified": len(source_files),
        "all_source_files_verified": len(verified_source_paths),
        "source_constraints_retained": constraints_count,
        "catalog_links_cross_checked": len(catalog_urls),
        "case_sensitive_archive_overrides": case_overrides,
        "archive_sha256": archive_hashes,
        "operations_without_direct_source": dict(Counter(
            r["kind"] for r in records if not r["source"])),
        "failures": failures,
        "inventory_scope": "All core/alloc/std declaration pages, associated anchors and implementation relations in the pinned documentation archive; all Rust library source files checked against the source archive",
        "documentation_inventory_extracted": not failures,
        "native_declarations_typechecked": False,
        "cfg_branches_compiled": False,
        "note": "Run validate.py for declaration closure, stability contexts, supporting-protocol exceptions and rule-assignment checks. Extraction is not compiler, soundness or parity evidence.",
    }
    (args.output / "audit-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps({k: v for k, v in summary.items() if k != "failures"}, indent=2))
    print(f"Failures: {len(failures)}", flush=True)
    if failures:
        print(json.dumps(failures[:15], indent=2))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
