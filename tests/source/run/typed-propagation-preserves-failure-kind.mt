
copy enum Error { Bad; Missing }
fn validate(value: i32): i32 throws Error {
    if value < 0 { throw Error::Bad }
    value
}
fn twice(value: i32) throws Error { (try validate(value)) * 2 }
fn main() {
    let first = capture twice(21)
    let second = capture twice(-1)
    let answer = match first { success(value) => value, failure(_) => 0 }
    let failed = match second { success(_) => false, failure(Error::Bad) => true, failure(Error::Missing) => false }
    if answer == 42 && failed { 0 } else { 1 }
}
