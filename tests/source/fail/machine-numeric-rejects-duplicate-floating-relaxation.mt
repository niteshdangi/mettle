// expect-error: attribute 3:21 duplicate floating relaxation

@fast_math(contract,contract)
module numeric { pub fn value():i32{42} }
fn main(){0}
