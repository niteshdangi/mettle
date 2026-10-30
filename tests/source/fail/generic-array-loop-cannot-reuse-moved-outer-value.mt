// expect-error: ownership 5:44 binding 'owner' may have been moved

type Owned { value: i32 }
fn wrong<const N:i32>(values:read [i32;N], owner:take Owned):Unit {
    for value in values { let moved = take owner }
}
fn main():i32{0}
