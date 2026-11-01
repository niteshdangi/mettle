// expect-exit: 0
// profiles: debug release

import alloc.string.{String, ToString}
import core.float
import core.text.Text

fn rendered_is<T: ToString + unsized>(value: read T, expected: read Text): bool {
    let output = T.(ToString).to_string(value)
    output.as_text() == expected
}

fn main(): i32 {
    if !rendered_is(1.5f32, "1.5") || !rendered_is(-1.5f64, "-1.5") {
        return 1
    }
    if !rendered_is(0.0f32, "0") || !rendered_is(-0.0f32, "-0") ||
       !rendered_is(0.0f64, "0") || !rendered_is(-0.0f64, "-0") {
        return 2
    }
    if !rendered_is(f32.NAN, "NaN") || !rendered_is(f64.NAN, "NaN") ||
       !rendered_is(f32.INFINITY, "inf") || !rendered_is(f64.INFINITY, "inf") ||
       !rendered_is(f32.NEG_INFINITY, "-inf") || !rendered_is(f64.NEG_INFINITY, "-inf") {
        return 3
    }
    if !rendered_is<Text>("", "") || !rendered_is<Text>("owned text", "owned text") {
        return 4
    }
    let original = alloc.string.from_text("unchanged")
    var output = original.to_string()
    output.push_str(" independently")
    if original.as_text() != "unchanged" || output.as_text() != "unchanged independently" {
        return 5
    }
    0
}
