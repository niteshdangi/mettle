import core.clone.Clone
import core.ffi.VaList

fn duplicate<region frame>(
    read cursor: VaList<region frame>
): VaList<region frame> {
    VaList<region frame>.(Clone).clone(cursor)
}

fn main(): i32 { 0 }
