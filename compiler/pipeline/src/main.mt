import mettle_foundation.Diagnostics
import mettle_frontend.{ CheckedModule, check_module }
import mettle_syntax.{ Parsed, parse }
pub import mettle_frontend.{ CheckError, CheckPhase }

pub type CheckedSource {
    pub syntax: Parsed
    pub facts: CheckedModule
}

pub enum Analysis {
    SyntaxErrors(Diagnostics),
    SemanticError(CheckError),
    Checked(CheckedSource)
}

pub fn analyze_source(read bytes: [u8], source: u32): Analysis {
    let parsed = parse(bytes, source)
    if parsed.diagnostics.error_count != 0 {
        return Analysis.SyntaxErrors(take parsed.diagnostics)
    }
    match take capture check_module(bytes, parsed) {
        success(facts) => Analysis.Checked(CheckedSource(take parsed, take facts)),
        failure(error) => Analysis.SemanticError(error)
    }
}
