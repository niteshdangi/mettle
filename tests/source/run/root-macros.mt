// expect-exit: 0
// profiles: debug release

import core.text.Text

const INVOCATION_LINE: u32 = line!()
const CONTENT: read Text = include_str!("root-macros-text.txt")
const BYTES: read [u8; 15] = include_bytes!("root-macros-text.txt")
include!("../support/root-macros-included.mt")

fn macro_column(): u32 {
    column!()
}

module macro_scope {
    pub fn path(): read core.text.Text from static { module_path!() }
}

fn main(): i32 {
    if INVOCATION_LINE != 6u32 || macro_column() != 5u32 { return 1 }
    if !file!().ends_with("root-macros.mt") ||
       macro_scope.path() != "macro_scope" { return 2 }
    if concat!("Mettle", " ", 2, true) != "Mettle 2true" { return 3 }
    if stringify!(left + right) != "left + right" { return 4 }
    if concat!("escaped\n", '\t', 7u32) != "escaped\n\t7" { return 9 }
    if stringify!((left, [right])) != "(left, [right])" { return 10 }
    if !cfg!(target_pointer_width = "64") { return 5 }
    if cfg_select!(cfg(target_pointer_width = "64") => 64, _ => 32) != 64 {
        return 6
    }
    if CONTENT != "included bytes\n" || BYTES.len() != 15usize { return 7 }
    if INCLUDED != 42 { return 8 }
    0
}
