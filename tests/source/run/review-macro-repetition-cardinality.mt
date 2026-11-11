macro optional { ($($x:expr),*) => { $(let _ = $x;)? }; }
macro nonempty { ($($x:expr),*) => { $(let _ = $x;)+ }; }
fn main(): i32 {
    optional!();
    optional!(1);
    nonempty!(1, 2);
    0
}
