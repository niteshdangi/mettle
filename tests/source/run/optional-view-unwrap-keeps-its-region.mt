
import core.text.Text;
fn word_free(w: read Text): Unit {}
fn first(t: read Text): (read Text from t)? { present(read t) }
fn b(text: read Text): Unit { let x = first(text).unwrap(); word_free(x) }
fn main(): i32 { b("x"); 0 }
