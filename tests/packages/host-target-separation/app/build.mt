import host_target_app.helper

fn main(): i32 {
    std.io.print("mettle:reproducible\n")
    helper.host_value() - 99
}
