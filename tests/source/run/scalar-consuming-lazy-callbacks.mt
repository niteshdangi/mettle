// profiles: debug release
import core.cmp.Ordering
import core.num
import core.option

static mut DROPS: i32 = 0
static mut CALLS: i32 = 0
type Token {
    value: i32
    drop { unsafe { DROPS += 1 } }
}
fn consume(take token: Token): Unit {
    unsafe { CALLS += token.value }
}

fn main(): i32 {
    {
        let token = Token(3)
        let result = true.then<Token>(take fn(): Token { token })
        match take result {
            present(value) => { consume(take value) },
            none => { return 1 }
        }
    }
    if unsafe { DROPS != 1 || CALLS != 3 } { return 2 }
    {
        let token = Token(10)
        let result = false.then(take fn(): Token { token })
        if result.is_present() { return 3 }
    }
    if unsafe { DROPS != 2 || CALLS != 3 } { return 4 }
    {
        let token = Token(5)
        let result = false.ok_or_else<Token>(take fn(): Token { token })
        match take result {
            failure(value) => { consume(take value) },
            success(_) => { return 5 }
        }
    }
    {
        let token = Token(20)
        let result = true.ok_or_else(take fn(): Token { token })
        match take result {
            success(_) => {},
            failure(_) => { return 6 }
        }
    }
    if unsafe { DROPS != 4 || CALLS != 8 } { return 7 }
    {
        let token = Token(7)
        let order = Ordering.Equal.then_with(take fn(): Ordering {
            consume(take token)
            Ordering.Greater
        })
        if !order.is_gt() { return 8 }
    }
    {
        let token = Token(30)
        let order = Ordering.Less.then_with(take fn(): Ordering {
            consume(take token)
            Ordering.Greater
        })
        if !order.is_lt() { return 9 }
    }
    if unsafe { DROPS == 6 && CALLS == 15 } { 0 } else { 10 }
}
