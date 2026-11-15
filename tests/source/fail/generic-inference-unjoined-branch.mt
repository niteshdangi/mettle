// expect-error: type 11:23 cannot infer generic argument 'B'
// expect-error: type 11:40 cannot infer generic argument 'B'
// expect-error: type 21:5 cannot infer generic argument
// expect-error: type 21:5 unsatisfied interface obligation
// expect-error: type 32:5 cannot infer generic argument 'R'
// expect-error: type 32:23 cannot infer generic arguments of variant
// expect-error: type 32:45 cannot infer generic arguments of variant
enum Either<A, B> { Left(A); Right(B) }
fn left<A, B>(take value: A): Either<A, B> { Either.Left(value) }
fn main(): i32 {
    let a = if true { left(1) } else { left(2) };
    0
}

interface QueryChoice<Q> {}
type Choice {}
extend Choice implements QueryChoice<i32> {}
extend Choice implements QueryChoice<i64> {}
fn inspect<Q, R: QueryChoice<Q>>(read choice: R): i32 { 0 }
fn ambiguous(): i32 {
    inspect(Choice())
}

enum QueryBound<T> { Included(T); Unbounded }
interface QueryRange<Q: unsized> {}
extend<T> (QueryBound<T>, QueryBound<T>) implements QueryRange<T> {}
extend<region r, T: unsized>
    (QueryBound<read T from r>, QueryBound<read T from r>)
    implements QueryRange<T> {}
fn rangeQuery<Q: unsized, R: QueryRange<Q>>(read key: Q, take bounds: R): i32 { 0 }
fn ambiguousRange(): i32 {
    rangeQuery(1i32, (QueryBound.Unbounded, QueryBound.Unbounded))
}
