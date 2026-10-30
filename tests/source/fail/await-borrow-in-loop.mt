// expect-error: feature 7:5 `view` is a borrow that is used by an awaiting loop

async fn ready(): i32 { 1 }

async fn f(): i32 {
    let value = 1
    let view = read value
    while true {
        let n = await ready()
        view + n
    }
    0
}

fn main(): i32 { 0 }
