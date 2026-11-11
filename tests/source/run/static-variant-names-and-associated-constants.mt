copy enum Number { Pair { first: i32; second: i32 } }
type Answer {}
extend Answer { const VALUE: i32 = 42 }

static PAIR: Number = Number.Pair(second: 22, first: 20)
static ANSWER: i32 = Answer.VALUE

fn main(): i32 {
    match PAIR {
        Number.Pair { first: left, second: right } =>
            if left == 20 && right == 22 && ANSWER == 42 { 0 } else { 1 }
    }
}
