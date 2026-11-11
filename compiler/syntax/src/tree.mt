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
        Return, Break, Continue, If, While, Loop,
        TypeGroup, TypeTuple, TypeSlice, TypeArray, TypePointer,
        TypeOwner, TypePinned, TypeBorrow, TypeOptional, TypeSources,
        TypeApply, TypeArguments, TypeArgument, TypeConstArgument, TypeRegionArgument,
        TypeBinders, TypeFor, TypeErased, TypeOpaque, TypeProjection, TypeOutcome,
        TypeCallable, TypeModifier, TypeParameters, TypeParameter, TypeVariadic, TypeEffect,
        GenericApply, GenericParameters, GenericParameter, Bounds, Constraints, Constraint,
        DefaultType, DefaultValue, Visibility, Modifier,
        ModuleDeclaration, ModuleBody, Import, ImportPath, ImportAlias, ImportGroup, ImportName,
        ImportGlob,
        Product, Union, Enumeration, VariantDeclaration, Members, FieldDeclaration,
        Interface, Extension, NegativeExtension, AssociatedType, Constant, Static,
        Alias, Foreign, Constructor, Destructor, Attribute, TokenTree, MacroDefinition,
        PatternWildcard, PatternLiteral, PatternTuple, PatternArray, PatternRest,
        PatternVariant, PatternProduct, PatternField, PatternAt, PatternOr, PatternRange,
        Match, Arm, Guard, Condition, Conditions, For, Label, LetElse, Closure,
        NamedArgument, OptionalField, Projection, Unsafe, Await, Try, Capture, Throw,
        None, Present, Success, Failure, Owner, Interpolation, FormatPiece, FormatHole,
        MacroInvocation
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
        NodeKind.While => "while", NodeKind.Loop => "loop",
        NodeKind.TypeGroup => "type-group", NodeKind.TypeTuple => "type-tuple",
        NodeKind.TypeSlice => "type-slice", NodeKind.TypeArray => "type-array",
        NodeKind.TypePointer => "type-pointer", NodeKind.TypeOwner => "type-owner",
        NodeKind.TypePinned => "type-pinned", NodeKind.TypeBorrow => "type-borrow",
        NodeKind.TypeOptional => "type-optional", NodeKind.TypeSources => "type-sources",
        NodeKind.TypeApply => "type-apply", NodeKind.TypeArguments => "type-arguments",
        NodeKind.TypeArgument => "type-argument",
        NodeKind.TypeConstArgument => "type-const-argument",
        NodeKind.TypeRegionArgument => "type-region-argument",
        NodeKind.TypeBinders => "type-binders",
        NodeKind.TypeFor => "type-for", NodeKind.TypeErased => "type-erased",
        NodeKind.TypeOpaque => "type-opaque",
        NodeKind.TypeProjection => "type-projection", NodeKind.TypeOutcome => "type-outcome",
        NodeKind.TypeCallable => "type-callable", NodeKind.TypeModifier => "type-modifier",
        NodeKind.TypeParameters => "type-parameters", NodeKind.TypeParameter => "type-parameter",
        NodeKind.TypeVariadic => "type-variadic", NodeKind.TypeEffect => "type-effect",
        NodeKind.GenericApply => "generic-apply",
        NodeKind.GenericParameters => "generic-parameters",
        NodeKind.GenericParameter => "generic-parameter", NodeKind.Bounds => "bounds",
        NodeKind.Constraints => "constraints", NodeKind.Constraint => "constraint",
        NodeKind.DefaultType => "default-type", NodeKind.DefaultValue => "default-value",
        NodeKind.Visibility => "visibility", NodeKind.Modifier => "modifier",
        NodeKind.ModuleDeclaration => "module-declaration", NodeKind.ModuleBody => "module-body",
        NodeKind.Import => "import", NodeKind.ImportPath => "import-path",
        NodeKind.ImportAlias => "import-alias", NodeKind.ImportGroup => "import-group",
        NodeKind.ImportName => "import-name", NodeKind.ImportGlob => "import-glob",
        NodeKind.Product => "product", NodeKind.Union => "union",
        NodeKind.Enumeration => "enumeration",
        NodeKind.VariantDeclaration => "variant-declaration", NodeKind.Members => "members",
        NodeKind.FieldDeclaration => "field-declaration", NodeKind.Interface => "interface",
        NodeKind.Extension => "extension", NodeKind.NegativeExtension => "negative-extension",
        NodeKind.AssociatedType => "associated-type", NodeKind.Constant => "constant",
        NodeKind.Static => "static",
        NodeKind.Alias => "alias", NodeKind.Foreign => "foreign",
        NodeKind.Constructor => "constructor",
        NodeKind.Destructor => "destructor", NodeKind.Attribute => "attribute",
        NodeKind.TokenTree => "token-tree",
        NodeKind.MacroDefinition => "macro-definition",
        NodeKind.PatternWildcard => "pattern-wildcard",
        NodeKind.PatternLiteral => "pattern-literal", NodeKind.PatternTuple => "pattern-tuple",
        NodeKind.PatternArray => "pattern-array", NodeKind.PatternRest => "pattern-rest",
        NodeKind.PatternVariant => "pattern-variant", NodeKind.PatternProduct => "pattern-product",
        NodeKind.PatternField => "pattern-field", NodeKind.PatternAt => "pattern-at",
        NodeKind.PatternOr => "pattern-or", NodeKind.PatternRange => "pattern-range",
        NodeKind.Match => "match", NodeKind.Arm => "arm", NodeKind.Guard => "guard",
        NodeKind.Condition => "condition", NodeKind.Conditions => "conditions",
        NodeKind.For => "for",
        NodeKind.Label => "label", NodeKind.LetElse => "let-else", NodeKind.Closure => "closure",
        NodeKind.NamedArgument => "named-argument", NodeKind.OptionalField => "optional-field",
        NodeKind.Projection => "projection", NodeKind.Unsafe => "unsafe", NodeKind.Await => "await",
        NodeKind.Try => "try", NodeKind.Capture => "capture", NodeKind.Throw => "throw",
        NodeKind.None => "none", NodeKind.Present => "present", NodeKind.Success => "success",
        NodeKind.Failure => "failure", NodeKind.Owner => "owner",
        NodeKind.Interpolation => "interpolation",
        NodeKind.FormatPiece => "format-piece", NodeKind.FormatHole => "format-hole",
        NodeKind.MacroInvocation => "macro-invocation"
    }
}
