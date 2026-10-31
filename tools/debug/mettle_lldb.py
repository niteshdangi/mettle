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


def slice_summary(value, _internal_dict):
    length = _unsigned(value.GetChildMemberWithName("length"))
    if length is None:
        return "slice <unavailable>"
    return f"slice len={length}"


def erased_summary(value, _internal_dict):
    data = _unsigned(value.GetChildMemberWithName("data_ptr"))
    alignment = _unsigned(value.GetChildMemberWithName("alignment"))
    witness = _unsigned(value.GetChildMemberWithName("witness"))
    if data is None or alignment is None or witness is None:
        return "erased value <unavailable>"
    return (f"erased data=0x{data:x} alignment={alignment} "
            f"witness=0x{witness:x}")


def _text(value):
    pointer = _unsigned(value.GetChildMemberWithName("data_ptr"))
    length = _unsigned(value.GetChildMemberWithName("length"))
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
    tag = _unsigned(value.GetChildMemberWithName("discriminant"))
    if tag is None:
        return "<variant unavailable>"
    name = value.GetTypeName() or ""
    labels = (("none", "present") if name.endswith("?")
              else ("success", "failure"))
    return labels[tag] if tag < len(labels) else "<invalid discriminant>"


def coroutine_summary(value, _internal_dict):
    if value.GetType().IsPointerType():
        value = value.Dereference()
        if not value.IsValid():
            return "state = <unavailable>"
    state = value.GetChildMemberWithName("state")
    raw = _unsigned(state)
    if raw is None:
        return "state = <unavailable>"
    tag = raw if raw < (1 << 31) else raw - (1 << 32)
    members = state.GetType().GetEnumMembers()
    for index in range(members.GetSize()):
        member = members.GetTypeEnumMemberAtIndex(index)
        if member.GetValueAsSigned() == tag:
            return f"state = {member.GetName()}"
    return "state = <invalid>"


def __lldb_init_module(debugger, _internal_dict):
    commands = [
        r"type summary add -w Mettle -x '(^|\.)List<.*>$' "
        r"-F mettle_lldb.list_summary",
        r"type summary add -w Mettle -x '^(read |mut )?\[.*\]$' "
        r"-F mettle_lldb.slice_summary",
        r"type summary add -w Mettle -x '^(read |mut )?any .+$' "
        r"-F mettle_lldb.erased_summary",
        r"type summary add -w Mettle -x '(^|\.)String<.*>$' "
        r"-F mettle_lldb.string_summary",
        r"type summary add -w Mettle -x '^(read |mut |ptr<read |ptr<mut )"
        r"(.*\.)?Text>?$' -F mettle_lldb.text_summary",
        r"type summary add -w Mettle -x '^\(.*\)\?$' "
        r"-F mettle_lldb.sum_summary",
        r"type summary add -w Mettle -x '^\(.* throws .*\)$' "
        r"-F mettle_lldb.sum_summary",
        r"type summary add -w Mettle -x "
        r"'^((read|mut) )?(.*\.)?CoroutineState<.*>$' "
        r"-F mettle_lldb.coroutine_summary",
        "type category enable Mettle",
    ]
    for command in commands:
        debugger.HandleCommand(command)
