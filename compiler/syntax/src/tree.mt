import alloc.vec.List
import core.text.Text
import mettle_foundation.{ Diagnostics, Span }
import super.token.Token

pub copy type NodeId { pub index: u32 }
pub copy type IndexRange { pub begin: u32; pub end: u32 }
pub copy enum NodeKind {
    Module, Function, Parameters, Parameter, TypeName, Error,
        Integer, Floating, Boolean, Character, Byte, Text, Name, Unit,
        Group, Tuple, Array, Repeat, Unary, Binary, Coalesce, Range,
        Call, Arguments, Field, Index, Cast, Block, Binding, Assign,
        Return, Break, Continue, If, While, Loop
}
extend NodeKind {
    pub fn is(other: NodeKind): bool { (self as u32) == (other as u32) }
}
pub copy type SyntaxNode {
    pub kind: NodeKind
    pub span: Span
    pub tokens: IndexRange
    pub children: IndexRange
    pub operation: u32?
    pub semicolon: bool
}
pub type Parsed {
    pub tokens: List<Token>
    pub nodes: List<SyntaxNode>
    pub children: List<NodeId>
    pub root: NodeId?
    pub diagnostics: Diagnostics
}

pub fn node_name(kind: NodeKind): read Text from static {
    match kind {
        NodeKind.Module => "module", NodeKind.Function => "function",
        NodeKind.Parameters => "parameters", NodeKind.Parameter => "parameter",
        NodeKind.TypeName => "type", NodeKind.Error => "error",
        NodeKind.Integer => "integer", NodeKind.Floating => "floating",
        NodeKind.Boolean => "boolean", NodeKind.Character => "character",
        NodeKind.Byte => "byte", NodeKind.Text => "text", NodeKind.Name => "name",
        NodeKind.Unit => "unit", NodeKind.Group => "group", NodeKind.Tuple => "tuple",
        NodeKind.Array => "array", NodeKind.Repeat => "repeat", NodeKind.Unary => "unary",
        NodeKind.Binary => "binary", NodeKind.Coalesce => "coalesce", NodeKind.Range => "range",
        NodeKind.Call => "call", NodeKind.Arguments => "arguments", NodeKind.Field => "field",
        NodeKind.Index => "index", NodeKind.Cast => "cast", NodeKind.Block => "block",
        NodeKind.Binding => "binding", NodeKind.Assign => "assign", NodeKind.Return => "return",
        NodeKind.Break => "break", NodeKind.Continue => "continue", NodeKind.If => "if",
        NodeKind.While => "while", NodeKind.Loop => "loop"
    }
}
