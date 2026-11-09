enum Either<A, B> { Left(A); Right(B) }
fn left<A, B>(take value: A): Either<A, B> { Either.Left(value) }
fn right<A, B>(take value: B): Either<A, B> { Either.Right(value) }
fn score(e: Either<i32, bool>): i32 {
    match e {
        Either.Left(n) => n,
        Either.Right(b) => if b { 100 } else { 200 }
    }
}
fn nested(n: i32): Either<i32, Either<bool, u8>> {
    let picked = match n {
        0 => left(7),
        1 => right(left(true)),
        _ => right(right(9u8))
    };
    picked
}
fn main(): i32 {
    let a = if true { left(1) } else { right(false) };
    let b = if false { left(2) } else { right(true) };
    let c = if true, true { left(3) } else { right(false) };
    let d = if false, true { left(4) } else { right(true) };
    if score(c) != 3 || score(d) != 100 { return 1 }
    let tail = match nested(2) {
        Either.Right(Either.Right(x)) => x as i32,
        _ => 0
    };
    if score(a) + score(b) + tail == 110 { 0 } else { 1 }
}
