// expect-error: region 8:10 view region or invariant payload does not satisfy its declared relationship
import core.text.Text

fn keep(take pair: (read Text from static, u16)): Unit {}

fn main(): i32 {
    let owner = alloc.string.from_text("local")
    keep((owner.as_text(), 0u16))
    0
}
