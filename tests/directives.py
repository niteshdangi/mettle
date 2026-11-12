"""Leading `// key: value` comment lines that configure one test program.

The directives are the run of lines at the very start of a source file that
match `// key: value`; the first other line (code, blank or an ordinary
comment) ends them. The lines stay in the file, so diagnostic line numbers
count them.
"""

import re

DIRECTIVE = re.compile(r"// ([\w-]+): ?(.*)$")


def parse(text):
    """Returns ({key: [value, ...]}, number of directive lines)."""
    found = {}
    count = 0
    for line in text.splitlines():
        match = DIRECTIVE.match(line)
        if not match:
            break
        found.setdefault(match.group(1), []).append(match.group(2))
        count += 1
    return found, count


def parse_error(entry):
    match = re.fullmatch(r"(\w+) ([1-9]\d*):([1-9]\d*) (.+)", entry)
    if not match:
        raise ValueError("expect-error must be `PHASE LINE:COL MESSAGE`")
    return match.groups()


def matches_error(source, expectation, stderr, *, source_suffix=None):
    phase, line, column, message = expectation
    if source_suffix is None:
        path = re.escape(str(source))
    else:
        path = r"(?:^|[/\\])" + r"[/\\]".join(
            re.escape(part) for part in source_suffix.replace("\\", "/").split("/"))
    intended = (path + re.escape(f":{line}:{column}: error[{phase}]:") +
                r"[^\n]*" + re.escape(message))
    return re.search(intended, stderr) is not None
