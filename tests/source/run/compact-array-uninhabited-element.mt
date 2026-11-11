fn impossible(value: [Never; 65]): i32 { match value {} }
fn empty(value: [Never; 0]): i32 { 42 }

fn main() {
    if empty([]) == 42 { 0 } else { 1 }
}
