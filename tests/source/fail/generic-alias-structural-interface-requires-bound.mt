// expect-error: type 9:1 unsatisfied interface obligation
interface Ready {}
interface OwnedType { type Owned; }
extend<T: Ready> [T] implements OwnedType { type Owned = usize }
enum Storage<region r, B: OwnedType + unsized> {
    Borrowed(read B from r);
    Owned(B.Owned)
}
alias Cow<region r, T> = Storage<region r, [T]>

fn main(): i32 { 0 }
