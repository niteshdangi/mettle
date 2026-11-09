// expect-error: type 5:23 cannot infer generic argument 'B'
enum Either<A, B> { Left(A); Right(B) }
fn left<A, B>(take value: A): Either<A, B> { Either.Left(value) }
fn main(): i32 {
    let a = if true { left(1) } else { left(2) };
    0
}
