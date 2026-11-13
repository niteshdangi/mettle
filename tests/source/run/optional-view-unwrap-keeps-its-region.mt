
import core.text.Text
fn word_free(read w: Text): Unit {}
fn first(read t: Text): (read Text from t)? { present(read t) }
fn b(read text: Text): Unit { let x = first(text).or_panic(); word_free(x) }
fn main(): i32 { b("x"); 0 }
