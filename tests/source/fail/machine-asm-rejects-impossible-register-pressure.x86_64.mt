// arch: x86_64
// expect-error: assembly 3:22 available register inventory
fn main() { unsafe { asm!("/* {v0} {v1} {v2} {v3} {v4} */",v0= in(reg_abcd) 1i64,v1= in(reg_abcd) 2i64,v2= in(reg_abcd) 3i64,v3= in(reg_abcd) 4i64,v4= in(reg_abcd) 5i64) }; 0 }
