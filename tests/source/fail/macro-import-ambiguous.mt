// expect-error: name 10:18 ambiguous macro import for 'value'
module first {
    pub macro value { () => { 20 }; }
}
module second {
    pub macro value { () => { 22 }; }
}
import first.value
import second.value
fn main(): i32 { value!() }
