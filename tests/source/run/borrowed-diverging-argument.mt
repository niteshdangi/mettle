
fn observe(value: read i32) {}
fn early() { observe({ return 42 }); 0 }
fn main() { if early() == 42 { 0 } else { 1 } }
