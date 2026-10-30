// expect-error: type 3:22 invalid primitive operation

fn main(){let result=42i64.checked_cast::<bool>();0}
