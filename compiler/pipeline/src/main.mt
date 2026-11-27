import alloc.hash_map.Map
import alloc.vec.List
import mettle_ir.VerifiedProgram
import mettle_middle.{ LoweringError, lower }

pub import mettle_frontend.{ CheckError, CheckPhase, SourceModule, active_items, check_modules, external_modules }

pub copy enum CompileError { Check(CheckError), Lower(LoweringError) }

pub fn compile_modules(read sources: List<SourceModule>, read mounts: List<Map<List<u8>, usize>>,
    executable: bool): VerifiedProgram throws CompileError {
    let checked = match take capture check_modules(sources, mounts, executable) {
        success(checked) => checked,
        failure(error) => throw CompileError.Check(error)
    }
    match take capture lower(sources, checked) {
        success(verified) => verified,
        failure(error) => throw CompileError.Lower(error)
    }
}
