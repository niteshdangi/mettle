// expect-error: ownership 7:28 moved
import std.process.{Command, Stdio}

fn conflict(take config: Stdio): Unit {
    var command = Command.new("/bin/true")
    command.stdout(config)
    let _ = command.stderr(config)
}

fn main(): i32 { 0 }
