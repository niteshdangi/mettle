import alloc.vec.List
import core.text.Text
import super.source.Span

pub copy enum Phase { Lex, Feature, Limit }
pub copy type Issue { pub phase: Phase; pub span: Span; pub message: read Text from static }
pub type Diagnostics { pub issues: List<Issue>; pub error_count: usize }

extend Diagnostics {
    pub init() { self.issues = List<Issue>(); self.error_count = 0usize }

    pub mut fn report(phase: Phase, span: Span, read message: Text from static): Unit {
        self.error_count += 1
        if self.issues.len() < 100 { self.issues.push(Issue(phase, span, message)) }
    }
}
