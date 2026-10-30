fn run(): i32 throws std.io.Error {
    let addresses = try std.net.resolve("localhost", 8080u16)
    if addresses.is_empty() { return 1 }
    var found = false
    var i = 0usize
    while i < addresses.len() {
        if addresses[i].ip.is_loopback() { found = true }
        i += 1usize
    }
    if found { 0 } else { 2 }
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(error) => 100
    }
}
