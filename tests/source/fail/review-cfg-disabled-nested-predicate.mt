// expect-error: attribute 4:10 unknown cfg predicate
@cfg(false)
module disabled {
    @cfg(unknown)
    fn value(): i32 { 0 }
}
fn main(): i32 { 0 }
