#!/usr/bin/env python3
"""Generate Mettle's compact Unicode 17.0.0 core character tables."""

import argparse
from pathlib import Path

VERSION = "17.0.0"
HEADER_FILES = (
    "DerivedCoreProperties.txt",
    "PropList.txt",
    "SpecialCasing.txt",
    "CaseFolding.txt",
    "DerivedGeneralCategory.txt",
)
# UnicodeData.txt is the one UCD input without a release/version header.
PROPERTIES = (
    ("ALPHABETIC_RANGES", "Alphabetic"),
    ("LOWERCASE_RANGES", "Lowercase"),
    ("UPPERCASE_RANGES", "Uppercase"),
    ("CASED_RANGES", "Cased"),
    ("CASE_IGNORABLE_RANGES", "Case_Ignorable"),
    ("GRAPHEME_EXTEND_RANGES", "Grapheme_Extend"),
    ("DEFAULT_IGNORABLE_RANGES", "Default_Ignorable_Code_Point"),
)


def read_inputs(directory):
    files = {}
    for name in ("UnicodeData.txt", *HEADER_FILES):
        source = (directory / "extracted" / name if name == "DerivedGeneralCategory.txt"
                  else directory / name)
        files[name] = source.read_text(encoding="utf-8")
    for name in HEADER_FILES:
        expected = f"{name.removesuffix('.txt')}-{VERSION}.txt"
        if not any(expected in line for line in files[name].splitlines()[:20]):
            raise ValueError(f"{name}: expected a {VERSION} UCD header")
    return files


def codepoint_range(text):
    parts = text.strip().split("..")
    start = int(parts[0], 16)
    return start, int(parts[-1], 16)


def merge_ranges(ranges):
    result = []
    for start, end in sorted(ranges):
        if result and start <= result[-1][1] + 1:
            result[-1] = (result[-1][0], max(result[-1][1], end))
        else:
            result.append((start, end))
    return result


def property_ranges(text, wanted):
    ranges = {name: [] for name in wanted}
    for line in text.splitlines():
        record = line.split("#", 1)[0].strip()
        if not record:
            continue
        span, property_name = (part.strip() for part in record.split(";", 1))
        if property_name in ranges:
            ranges[property_name].append(codepoint_range(span))
    return {name: merge_ranges(items) for name, items in ranges.items()}


def parse_unicode_data(text):
    numeric = []
    lowercase = {}
    uppercase = {}
    pending = None
    numeric_categories = {"Nd", "Nl", "No"}
    for line_number, line in enumerate(text.splitlines(), 1):
        fields = line.split(";")
        if len(fields) != 15:
            raise ValueError(f"UnicodeData.txt:{line_number}: expected 15 fields")
        scalar = int(fields[0], 16)
        name, category = fields[1], fields[2]
        if name.endswith(", First>"):
            if pending is not None:
                raise ValueError(f"UnicodeData.txt:{line_number}: nested First record")
            pending = (scalar, category)
            continue
        if name.endswith(", Last>"):
            if pending is None or pending[1] != category or scalar < pending[0]:
                raise ValueError(f"UnicodeData.txt:{line_number}: unmatched Last record")
            if category in numeric_categories:
                numeric.append((pending[0], scalar))
            pending = None
            continue
        if pending is not None:
            raise ValueError(f"UnicodeData.txt:{line_number}: missing Last record")
        if category in numeric_categories:
            numeric.append((scalar, scalar))
        if fields[13]:
            lowercase[scalar] = (int(fields[13], 16),)
        if fields[12]:
            uppercase[scalar] = (int(fields[12], 16),)
    if pending is not None:
        raise ValueError("UnicodeData.txt: unterminated First record")
    return merge_ranges(numeric), lowercase, uppercase


def parse_special_casing(text, lowercase, uppercase):
    for line_number, line in enumerate(text.splitlines(), 1):
        record = line.split("#", 1)[0].strip()
        if not record:
            continue
        fields = [part.strip() for part in record.split(";")]
        if len(fields) == 6 and not fields[-1]:
            fields.pop()
        if len(fields) != 5:
            raise ValueError(f"SpecialCasing.txt:{line_number}: expected 5 fields")
        if fields[4]:
            continue
        scalar = int(fields[0], 16)
        for column, mappings in ((1, lowercase), (3, uppercase)):
            if fields[column]:
                result = tuple(int(value, 16) for value in fields[column].split())
                if not 1 <= len(result) <= 3:
                    raise ValueError(
                        f"SpecialCasing.txt:{line_number}: mapping length is not 1..3"
                    )
                mappings[scalar] = result


def format_scalar(value):
    return f"0x{value:04x}u32"


def format_array(name, values):
    lines = [f"static {name}: [u32; {len(values)}] = ["]
    for start in range(0, len(values), 8):
        chunk = ", ".join(format_scalar(value) for value in values[start:start + 8])
        lines.append(f"    {chunk},")
    lines.append("]")
    return "\n".join(lines)


def flatten_ranges(ranges):
    return [value for start, end in ranges for value in (start, end)]


def flatten_mappings(mappings):
    values = []
    for scalar, result in sorted(mappings.items()):
        if result == (scalar,):
            continue
        values.extend((scalar, len(result), *result, *([0] * (3 - len(result)))))
    return values


def render_module(files):
    core = property_ranges(
        files["DerivedCoreProperties.txt"], {name for _, name in PROPERTIES}
    )
    white_space = property_ranges(files["PropList.txt"], {"White_Space"})[
        "White_Space"
    ]
    numeric, lowercase, uppercase = parse_unicode_data(files["UnicodeData.txt"])
    parse_special_casing(files["SpecialCasing.txt"], lowercase, uppercase)
    categories = property_ranges(files["DerivedGeneralCategory.txt"], {"Cc", "Co", "Cf", "Cn"})
    debug_escape = merge_ranges(span for ranges in categories.values() for span in ranges)

    tables = [
        (name, flatten_ranges(core[property_name]))
        for name, property_name in PROPERTIES
    ]
    tables.extend((
        ("WHITE_SPACE_RANGES", flatten_ranges(white_space)),
        ("NUMERIC_RANGES", flatten_ranges(numeric)),
        ("DEBUG_ESCAPE_RANGES", flatten_ranges(debug_escape)),
        ("LOWERCASE_MAP", flatten_mappings(lowercase)),
        ("UPPERCASE_MAP", flatten_mappings(uppercase)),
    ))
    sections = [
        "// Generated by tools/unicode_tables.py; do not edit.",
        f"// Unicode Character Database {VERSION}; see UNICODE-LICENSE.txt.",
        "",
        *[format_array(name, values) for name, values in tables],
        "",
        "fn contains(read ranges: [u32], scalar: u32): bool {",
        "    var low = 0usize",
        "    var high = ranges.len() / 2usize",
        "    while low < high {",
        "        let middle = low + (high - low) / 2usize",
        "        let start = ranges[middle * 2usize]",
        "        let end = ranges[middle * 2usize + 1usize]",
        "        if scalar < start {",
        "            high = middle",
        "        } else if scalar > end {",
        "            low = middle + 1usize",
        "        } else {",
        "            return true",
        "        }",
        "    }",
        "    false",
        "}",
        "",
    ]
    for name, _ in PROPERTIES:
        function = name.removesuffix("_RANGES").lower()
        sections.extend((
            f"pub parent fn is_{function}(scalar: u32): bool {{",
            f"    contains(read {name}, scalar)",
            "}",
            "",
        ))
    sections.extend((
        "pub parent fn is_white_space(scalar: u32): bool {",
        "    contains(read WHITE_SPACE_RANGES, scalar)",
        "}",
        "",
        "pub parent fn is_numeric(scalar: u32): bool {",
        "    contains(read NUMERIC_RANGES, scalar)",
        "}",
        "",
        "pub parent fn is_debug_escape(scalar: u32, escape_grapheme_extend: bool): bool {",
        "    contains(read DEBUG_ESCAPE_RANGES, scalar) || is_white_space(scalar) ||",
        "        is_default_ignorable(scalar) ||",
        "        (escape_grapheme_extend && is_grapheme_extend(scalar))",
        "}",
        "",
        "fn find_mapping(read table: [u32], scalar: u32): [u32; 4] {",
        "    var low = 0usize",
        "    var high = table.len() / 5usize",
        "    while low < high {",
        "        let middle = low + (high - low) / 2usize",
        "        let offset = middle * 5usize",
        "        let key = table[offset]",
        "        if scalar < key {",
        "            high = middle",
        "        } else if scalar > key {",
        "            low = middle + 1usize",
        "        } else {",
        "            return [table[offset + 1usize], table[offset + 2usize],",
        "                table[offset + 3usize], table[offset + 4usize]]",
        "        }",
        "    }",
        "    [1u32, scalar, 0u32, 0u32]",
        "}",
        "",
        "pub parent fn lowercase(scalar: u32): [u32; 4] {",
        "    find_mapping(read LOWERCASE_MAP, scalar)",
        "}",
        "",
        "pub parent fn uppercase(scalar: u32): [u32; 4] {",
        "    find_mapping(read UPPERCASE_MAP, scalar)",
        "}",
        "",
    ))
    return "\n".join(sections)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ucd_dir", type=Path, help="directory containing the UCD files")
    parser.add_argument("output", type=Path, help="generated unicode_data.mt path")
    args = parser.parse_args()
    files = read_inputs(args.ucd_dir)
    output = render_module(files)
    with args.output.open("w", encoding="utf-8", newline="\n") as destination:
        destination.write(output)
    print(f"Wrote {args.output}: Unicode {VERSION}")


if __name__ == "__main__":
    main()
