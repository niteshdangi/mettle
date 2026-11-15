// profiles: debug release
import core.text.Text

const INVOCATION_LINE: u32 = line!()
const CONTENT: read Text from static = include_str!("i17-char-escape-fused.mt")
const SETTING: read Text from static = env!("PATH")

module included {
    include!("i17-hint-operations.mt")
}

module scope {
    pub fn path(): read Text from static { module_path!() }
}

fn main(): i32 {
    let bytes = include_bytes!("i17-char-escape-fused.mt")
    if INVOCATION_LINE != 4u32 || column!() == 0u32 { return 1 }
    if !file!().ends_with("i17-root-builtins.mt") || scope.path() != "scope" { return 2 }
    if concat!("Mettle", " ", 2, true) != "Mettle 2true" { return 3 }
    if stringify!((left, [right])) != "(left, [right])" { return 4 }
    if !cfg!(target_pointer_width = "64") { return 5 }
    if cfg_select!(cfg(target_pointer_width = "64") => 64, _ => 32) != 64 { return 6 }
    if CONTENT.len() == 0usize || core.mem.size_of_val(bytes) != CONTENT.len() { return 7 }
    if SETTING.len() == 0usize { return 8 }
    match option_env!("PATH") {
        present(value) => if value != SETTING { return 9 },
        none => { return 10 }
    }
    0
}
