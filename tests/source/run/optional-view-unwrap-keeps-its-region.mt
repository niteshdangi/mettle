
import core.text.Text
fn word_free(read w: Text): Unit {}
fn first(read t: Text): (read Text from t)? { present(read t) }
fn b(read text: Text): Unit { let x = first(text).or_panic(); word_free(x) }

type Record { value: usize? }

fn get<region r>(read input: [u8] from r, record: Record): usize {
    if let present(value) = record.value { return value }
    input.len()
}

fn main(): i32 {
    b("x")
    if get(b"", Record(present(42usize))) == 42usize && get(b"abc", Record(none)) == 3usize { 0 }
    else { 1 }
}
