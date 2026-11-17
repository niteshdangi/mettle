copy type Record { value: i32 }

fn record(flag: bool) {
    if flag { Record(42) } else { wrapped(true).0[0] }
}

fn wrapped(flag: bool) { ([record(flag)],) }

fn main() {
    if wrapped(false).0[0].value == 42 { 0 } else { 1 }
}
