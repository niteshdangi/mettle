import alloc.string.String

fn main(): i32 {
    let sharp_s = "ß".to_uppercase()
    if sharp_s.as_text() != "SS" { return 1 }
    let dotted_i = "\u{130}".to_lowercase()
    if dotted_i.as_text() != "i\u{307}" { return 2 }
    let final_sigma = "ΟΔΟΣ".to_lowercase()
    if final_sigma.as_text() != "οδος" { return 3 }
    let medial_sigma = "ΟΣΑ".to_lowercase()
    if medial_sigma.as_text() != "οσα" { return 4 }
    let accented = "ÉCOLE".to_lowercase()
    if accented.as_text() != "école" { return 5 }
    let expanded = "straße".to_uppercase()
    if expanded.as_text() != "STRASSE" { return 6 }
    0
}
