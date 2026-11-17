macro optional { ($($x:expr),*) => { $(let _ = $x;)? }; }
macro nonempty { ($($x:expr),*) => { $(let _ = $x;)+ }; }
macro final {
    ($($prefix:ident => $field:literal,)* ; $last:ident => $value:literal) => { $value };
}
macro rows {
    ($bias:expr; $([$($value:expr),*]),*) => {
        0 $(+ (0 $(+ $value)* $(+ $value)* + $bias))* $(+ (0 $(+ $value)*))*
    };
}
fn main(): i32 {
    optional!();
    optional!(1);
    nonempty!(1, 2);
    if rows!(10; [1, 2], [], [3]) != 48 { return 1 }
    final!(
        A => 0, B => 1,
        ; C => 2
    ) + final!(; A => 0) + final!(A => 0,
        B => 1
    ) - 3
}
