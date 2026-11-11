// expect-exit: 0
import std.task
import std.io.{Error, ErrorKind}
import std.io

async fn fail(code: i32): i32 throws Error {
    if code > 0 { throw io.from_kind(ErrorKind.Unsupported) }
    code
}

async fn forward(code: i32): i32 throws Error {
    let result = await fail(code)
    match take result {
        success(value) => value,
        failure(error) => throw error
    }
}

async fn outcome(): bool {
    let result = await forward(1)
    match take result {
        success(_) => false,
        failure(error) => error.kind().is(ErrorKind.Unsupported)
    }
}

fn main(): i32 {
    if task.block_on(outcome()) { 0 } else { 1 }
}
