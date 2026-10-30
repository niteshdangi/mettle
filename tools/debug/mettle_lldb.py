"""LLDB summaries for Mettle's current native library representations."""

import lldb


def _unsigned(value):
    if not value.IsValid():
        return None
    error = lldb.SBError()
    result = value.GetValueAsUnsigned(error)
    return result if error.Success() else None


def list_summary(value, _internal_dict):
    length = _unsigned(value.GetChildMemberWithName("len"))
    capacity = _unsigned(value.GetChildMemberWithName("cap"))
    if length is None or capacity is None:
        return "List <unavailable>"
    return f"List len={length} cap={capacity}"


def _text(value):
    pointer = _unsigned(value.GetChildMemberWithName("ptr"))
    length = _unsigned(value.GetChildMemberWithName("len"))
    if pointer is None or length is None:
        return "<unavailable>"
    if not length:
        return '""'
    if not pointer:
        return "<invalid pointer>"
    error = lldb.SBError()
    size = min(length, 256)
    data = value.GetProcess().ReadMemory(pointer, size, error)
    if not error.Success() or len(data) != size:
        return "<unavailable>"
    text = data.decode("utf-8", errors="replace")
    suffix = "..." if size < length else ""
    return f"{text!r}{suffix}"


def text_summary(value, _internal_dict):
    return _text(value)


def string_summary(value, _internal_dict):
    return _text(value.GetChildMemberWithName("v"))


def sum_summary(value, _internal_dict):
    # Native optional/outcome values begin with the 32-bit ordinal. Read only
    # the discriminator; inactive payload fields are not safe to inspect.
    error = lldb.SBError()
    tag = value.GetData().GetUnsignedInt32(error, 0)
    if not error.Success():
        return "<variant unavailable>"
    name = value.GetTypeName() or ""
    labels = (("none", "present") if name.endswith("?")
              else ("success", "failure"))
    return labels[tag] if tag < len(labels) else "<invalid discriminant>"


def __lldb_init_module(debugger, _internal_dict):
    commands = [
        r"type summary add -w Mettle -x '(^|\.)List<.*>$' "
        r"-F mettle_lldb.list_summary",
        r"type summary add -w Mettle -x '(^|\.)String<.*>$' "
        r"-F mettle_lldb.string_summary",
        r"type summary add -w Mettle -x '^(read |mut |ptr<read |ptr<mut )"
        r"(.*\.)?Text>?$' -F mettle_lldb.text_summary",
        r"type summary add -w Mettle -x '^\(.*\)\?$' "
        r"-F mettle_lldb.sum_summary",
        r"type summary add -w Mettle -x '^\(.* throws .*\)$' "
        r"-F mettle_lldb.sum_summary",
        "type category enable Mettle",
    ]
    for command in commands:
        debugger.HandleCommand(command)
