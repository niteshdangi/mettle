import alloc.vec.new
import mettle_foundation.{ Diagnostics, Phase, Span }
import super.parser.{ parse, parse_assembly_arguments }
import super.token.{ Kind, Token }
import super.tree.{ NodeId, NodeKind, Parsed, SyntaxNode }

pub copy enum AssemblyPosition { Expression, ModuleItem }
pub copy enum AssemblyVariant { Inline, Naked, Global }

pub type AssemblyBuiltin {
    pub variant: AssemblyVariant
    pub span: Span
    pub arguments: Parsed
}

fn child(read tree: Parsed, node: SyntaxNode, index: usize): SyntaxNode {
    tree.nodes[tree.children[node.children.begin as usize + index].index as usize]
}

fn spelling(read bytes: [u8], span: Span, unquote: bool): read [u8] from bytes {
    let trim = if unquote { 1usize } else { 0usize }
    read bytes[span.begin as usize + trim..span.end as usize - trim]
}

pub fn parse_unshadowed_assembly(read bytes: [u8], read tree: Parsed, invocation: NodeId,
    position: AssemblyPosition, async_body: bool): AssemblyBuiltin? {
    if invocation.index as usize >= tree.nodes.len() { return none }
    let node = tree.nodes[invocation.index as usize]
    if !node.kind.is(NodeKind.MacroInvocation) || node.span.end as usize > bytes.len() { return none }
    let count = (node.children.end - node.children.begin) as usize
    if count < 2usize { return none }
    let args = child(tree, node, count - 1usize)
    if !args.kind.is(NodeKind.TokenTree) { return none }

    var first = child(tree, node, 0usize)
    var attributed = false
    let variant = match position {
        AssemblyPosition.Expression => {
            if count != 2usize { return none }
            let dotted = first.kind.is(NodeKind.Field)
            let last = if dotted { child(tree, first, 1usize) } else { first }
            var base = first
            while base.kind.is(NodeKind.Field) { base = child(tree, base, 0usize) }
            if !base.kind.is(NodeKind.Name) || !last.kind.is(NodeKind.Name) { return none }
            let quoted = tree.tokens[last.tokens.begin as usize].kind.is(Kind.QuotedWord)
            let name = spelling(bytes, last.span, !dotted && quoted)
            if name == "asm".as_bytes() { AssemblyVariant.Inline }
            else if name == "naked_asm".as_bytes() { AssemblyVariant.Naked }
            else if name == "global_asm".as_bytes() { AssemblyVariant.Global }
            else { return none }
        },
        AssemblyPosition.ModuleItem => {
            var index = 0usize
            while first.kind.is(NodeKind.Attribute) || first.kind.is(NodeKind.Visibility) {
                if first.kind.is(NodeKind.Attribute) { attributed = true }
                index += 1usize
                first = child(tree, node, index)
            }
            if !first.kind.is(NodeKind.Name) { return none }
            let name = spelling(bytes, first.span, false)
            let path_count = count - 1usize - index
            if path_count == 1usize && name == "global_asm".as_bytes() { AssemblyVariant.Global }
            else if path_count == 3usize && name == "core".as_bytes() &&
                spelling(bytes, child(tree, node, index + 1usize).span, false) == "arch".as_bytes() &&
                spelling(bytes, child(tree, node, index + 2usize).span, false) == "global_asm".as_bytes() {
                AssemblyVariant.Global
            } else { return none }
        }
    }

    let span = Span(node.span.source, first.span.begin, args.span.end)
    let arguments = if attributed {
        var diagnostics = Diagnostics()
        diagnostics.report(Phase.Feature, first.span, "attributes on global assembly are not implemented")
        Parsed(new<Token>(), new<SyntaxNode>(), new<NodeId>(), none, take diagnostics)
    } else { parse_assembly_arguments(bytes, args.span, async_body) }
    present(AssemblyBuiltin(variant, span, take arguments))
}

@test
fn builtin_assembly_expression_paths_and_spans(): Unit {
    let bytes = "fn f() { other.arch.asm!(\"nop\", in(reg) call(1, 2)); `naked_asm`!(\"nop\"); core.arch.`asm`!(\"nop\"); target().asm!(\"nop\"); ordinary!{} }".as_bytes()
    let tree = parse(bytes, 7u32)
    assert(tree.diagnostics.error_count == 0usize, "raw parser did not preserve the opaque invocations")
    var recognized = 0usize
    for index in 0usize..tree.nodes.len() {
        let candidate = parse_unshadowed_assembly(bytes, read tree, NodeId(index as u32), AssemblyPosition.Expression, false)
        let present(builtin) = take candidate else { continue }
        let present(root) = builtin.arguments.root else { core.panic.panic("valid assembly arguments failed") }
        if recognized == 0usize {
            let node = tree.nodes[index]
            let original = child(read tree, node, 1usize)
            let parsed = builtin.arguments.nodes[root.index as usize]
            assert((builtin.variant as u32) == (AssemblyVariant.Inline as u32) &&
                builtin.span.source == 7u32 && builtin.span.begin == 9u32 &&
                parsed.span.begin == original.span.begin && parsed.span.end == builtin.span.end, "qualified assembly lost its invocation or argument span")
            for offset in 0usize..(original.tokens.end - original.tokens.begin) as usize {
                let expected = tree.tokens[original.tokens.begin as usize + offset]
                let actual = builtin.arguments.tokens[offset]
                assert(actual.kind.is(expected.kind) && actual.span.source == 7u32 &&
                    actual.span.begin == expected.span.begin && actual.span.end == expected.span.end, "argument token spans changed")
            }
        } else {
            assert((builtin.variant as u32) == (AssemblyVariant.Naked as u32), "bare quoted naked assembly was not recognized")
        }
        recognized += 1usize
    }
    assert(recognized == 2usize, "selection accepted a quoted dotted suffix, computed callee, or ordinary macro")
}

@test
fn builtin_assembly_module_gate_and_malformed_arguments(): Unit {
    let bytes = "asm!(); other.global_asm!(); `global_asm`!(); pub core.arch.global_asm!(\"nop\"); @test global_asm!(); global_asm![\"nop\"]; global_asm!(strange(reg) 0)".as_bytes()
    let tree = parse(bytes, 3u32)
    assert(tree.diagnostics.error_count == 0usize, "raw module invocations must remain opaque")
    var recognized = 0usize
    for index in 0usize..tree.nodes.len() {
        let candidate = parse_unshadowed_assembly(bytes, read tree, NodeId(index as u32), AssemblyPosition.ModuleItem, false)
        let present(builtin) = take candidate else { continue }
        assert((builtin.variant as u32) == (AssemblyVariant.Global as u32), "module item selected non-global assembly")
        if recognized == 0usize {
            assert(builtin.arguments.root.is_present(), "qualified public global assembly did not parse")
        } else {
            assert(builtin.arguments.root.is_none() && builtin.arguments.diagnostics.error_count == 1usize, "invalid builtin did not report one error")
            let issue = builtin.arguments.diagnostics.issues[0usize]
            assert(issue.span.source == 3u32, "builtin diagnostic lost its source id")
            if recognized == 1usize {
                assert((issue.phase as u32) == (Phase.Feature as u32) && issue.span.begin == builtin.span.begin &&
                    issue.message == "attributes on global assembly are not implemented", "attributes did not gate module assembly")
            } else if recognized == 2usize {
                assert(issue.span.begin == builtin.span.begin + 11u32 &&
                    issue.message == "expected '('", "bracket delimiter diagnostic changed")
            } else {
                assert(issue.span.begin == builtin.span.begin + 19u32 &&
                    issue.message == "unknown assembly operand mode", "malformed operand diagnostic changed")
            }
        }
        recognized += 1usize
    }
    assert(recognized == 4usize, "module selection accepted an unrecognized assembly path")
}

@test
fn builtin_assembly_operands_obey_async_context(): Unit {
    let bytes = "async fn f() { asm!(\"nop\", in(reg) await work()) }".as_bytes()
    let tree = parse(bytes, 5u32)
    for index in 0usize..tree.nodes.len() {
        let invocation = NodeId(index as u32)
        if !tree.nodes[index].kind.is(NodeKind.MacroInvocation) { continue }
        let allowed = parse_unshadowed_assembly(bytes, read tree, invocation, AssemblyPosition.Expression, true)
        let rejected = parse_unshadowed_assembly(bytes, read tree, invocation, AssemblyPosition.Expression, false)
        let present(valid) = take allowed else { core.panic.panic("missing builtin in async body") }
        let present(invalid) = take rejected else { core.panic.panic("missing builtin in sync body") }
        assert(valid.arguments.root.is_present() && invalid.arguments.root.is_none() &&
            invalid.arguments.diagnostics.error_count == 1usize, "assembly operand ignored the enclosing await context")
        let issue = invalid.arguments.diagnostics.issues[0usize]
        assert(issue.span.begin == 35u32 && issue.message == "`await` is only valid inside an async function body",
            "await rejection lost its original location or diagnostic")
        return
    }
    core.panic.panic("no opaque assembly invocation")
}
