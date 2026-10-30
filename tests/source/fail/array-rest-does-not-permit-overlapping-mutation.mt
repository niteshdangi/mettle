// expect-error: ownership 2:77 live exclusive loan
fn main() { var values = [1,2,3]; match mut values { [first,rest @ ..] => { values[1] = 4; rest[0] += first } }; 0 }
