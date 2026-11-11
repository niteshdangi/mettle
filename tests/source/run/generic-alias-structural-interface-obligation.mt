interface OwnedType { type Owned; }
extend<T> [T] implements OwnedType { type Owned = usize }
enum Storage<region r, B: OwnedType + unsized> {
    Borrowed(read B from r);
    Owned(B.Owned)
}
alias Cow<region r, T> = Storage<region r, [T]>

interface Ready {}
interface ConditionalOwner { type Owned; }
extend<T: Ready> [T] implements ConditionalOwner { type Owned = usize }
enum ConditionalStorage<region r, B: ConditionalOwner + unsized> {
    Borrowed(read B from r);
    Owned(B.Owned)
}
alias ConditionalCow<region r, T: Ready> = ConditionalStorage<region r, [T]>

fn main(): i32 { 0 }
