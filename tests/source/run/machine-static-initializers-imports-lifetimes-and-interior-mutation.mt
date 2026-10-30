
module values {
    pub static ANSWER: i32 = 20 + 22;
    pub static WIDE: u128 = 340282366920938463463374607431768211455u128;
    pub static MAXIMUM: u128 = u128::MAX;
    pub static CELL: core::cell::UnsafeCell<i32> = core::cell::UnsafeCell::new(1);
    pub static FLAG: core::sync::atomic::AtomicU32 = core::sync::atomic::AtomicU32::new(0u32);
    pub static mut COUNT: i32 = 1;
}
import values::{ANSWER as NUMBER,CELL,FLAG}
static VIEW: read i32 from static = read values::ANSWER;
fn answer(): read i32 from static { read NUMBER }
fn forward(): read i32 from static { answer() }
fn main() {
    unsafe {
        *CELL.get() = 42
        values::COUNT += 1
    }
    FLAG.store(42u32,core::sync::atomic::Ordering::Relaxed)
    if *forward() == 42 && *VIEW == 42 &&
       values::WIDE == 340282366920938463463374607431768211455u128 &&
       values::WIDE == values::MAXIMUM &&
       unsafe { *CELL.get() == 42 && values::COUNT == 2 } &&
       FLAG.load(core::sync::atomic::Ordering::Relaxed) == 42u32 { 0 } else { 1 }
}
