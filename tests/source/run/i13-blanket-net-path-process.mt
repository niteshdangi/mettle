// expect-exit: 0
// profiles: debug release
// Blanket and auto-property evidence for net, path and process types. Each call instantiates the
// blanket trait row for a hosted std type. Pairs the compiler cannot satisfy are
// listed as gaps at the end of main; negative impls are evidenced in tests/source/fail.
fn any_ok<T: unsized + core.any.Any>(): Unit {}
fn borrow_ok<T: unsized + core.borrow.Borrow<T>>(): Unit {}
fn owned_ok<T: core.borrow.ToOwned>(): Unit {}
fn from_ok<T: core.convert.From<T>>(): Unit {}
fn into_ok<T: core.convert.Into<T>>(): Unit {}
fn tryfrom_ok<T: core.convert.TryFrom<T>>(): Unit {}
fn tryinto_ok<T: core.convert.TryInto<T>>(): Unit {}
fn string_ok<T: alloc.string.ToString>(): Unit {}
fn send_ok<T: unsized + Transferable>(): Unit {}
fn sync_ok<T: unsized + Shareable>(): Unit {}
alias A_net_IpAddr = std.net.IpAddr
alias A_net_Ipv4Addr = std.net.Ipv4Addr
alias A_net_Ipv6Addr = std.net.Ipv6Addr
alias A_net_SocketAddr = std.net.SocketAddr
alias A_net_TcpListener = std.net.TcpListener
alias A_net_TcpStream = std.net.TcpStream
alias A_net_UdpSocket = std.net.UdpSocket
alias A_path_Path = std.path.Path
alias A_path_PathBuf = std.path.PathBuf
alias A_process_Child = std.process.Child
alias A_process_Command = std.process.Command
alias A_process_ExitStatus = std.process.ExitStatus
alias A_process_Output = std.process.Output
alias A_process_Stdio = std.process.Stdio
fn main(): i32 {
    // net::IpAddr
    any_ok<A_net_IpAddr>()
    borrow_ok<A_net_IpAddr>()
    from_ok<A_net_IpAddr>()
    tryfrom_ok<A_net_IpAddr>()
    tryinto_ok<A_net_IpAddr>()
    into_ok<A_net_IpAddr>()
    send_ok<A_net_IpAddr>()
    sync_ok<A_net_IpAddr>()
    string_ok<A_net_IpAddr>()
    // net::Ipv4Addr
    any_ok<A_net_Ipv4Addr>()
    borrow_ok<A_net_Ipv4Addr>()
    from_ok<A_net_Ipv4Addr>()
    tryfrom_ok<A_net_Ipv4Addr>()
    tryinto_ok<A_net_Ipv4Addr>()
    into_ok<A_net_Ipv4Addr>()
    send_ok<A_net_Ipv4Addr>()
    sync_ok<A_net_Ipv4Addr>()
    string_ok<A_net_Ipv4Addr>()
    // net::Ipv6Addr
    any_ok<A_net_Ipv6Addr>()
    borrow_ok<A_net_Ipv6Addr>()
    from_ok<A_net_Ipv6Addr>()
    tryfrom_ok<A_net_Ipv6Addr>()
    tryinto_ok<A_net_Ipv6Addr>()
    into_ok<A_net_Ipv6Addr>()
    send_ok<A_net_Ipv6Addr>()
    sync_ok<A_net_Ipv6Addr>()
    string_ok<A_net_Ipv6Addr>()
    // net::SocketAddr
    any_ok<A_net_SocketAddr>()
    borrow_ok<A_net_SocketAddr>()
    from_ok<A_net_SocketAddr>()
    tryfrom_ok<A_net_SocketAddr>()
    tryinto_ok<A_net_SocketAddr>()
    into_ok<A_net_SocketAddr>()
    send_ok<A_net_SocketAddr>()
    sync_ok<A_net_SocketAddr>()
    string_ok<A_net_SocketAddr>()
    // net::TcpListener
    any_ok<A_net_TcpListener>()
    borrow_ok<A_net_TcpListener>()
    from_ok<A_net_TcpListener>()
    tryfrom_ok<A_net_TcpListener>()
    tryinto_ok<A_net_TcpListener>()
    into_ok<A_net_TcpListener>()
    send_ok<A_net_TcpListener>()
    sync_ok<A_net_TcpListener>()
    // net::TcpStream
    any_ok<A_net_TcpStream>()
    borrow_ok<A_net_TcpStream>()
    from_ok<A_net_TcpStream>()
    tryfrom_ok<A_net_TcpStream>()
    tryinto_ok<A_net_TcpStream>()
    into_ok<A_net_TcpStream>()
    send_ok<A_net_TcpStream>()
    sync_ok<A_net_TcpStream>()
    // net::UdpSocket
    any_ok<A_net_UdpSocket>()
    borrow_ok<A_net_UdpSocket>()
    from_ok<A_net_UdpSocket>()
    tryfrom_ok<A_net_UdpSocket>()
    tryinto_ok<A_net_UdpSocket>()
    into_ok<A_net_UdpSocket>()
    send_ok<A_net_UdpSocket>()
    sync_ok<A_net_UdpSocket>()
    // path::Path
    any_ok<A_path_Path>()
    borrow_ok<A_path_Path>()
    send_ok<A_path_Path>()
    sync_ok<A_path_Path>()
    // path::PathBuf
    any_ok<A_path_PathBuf>()
    borrow_ok<A_path_PathBuf>()
    from_ok<A_path_PathBuf>()
    tryfrom_ok<A_path_PathBuf>()
    tryinto_ok<A_path_PathBuf>()
    into_ok<A_path_PathBuf>()
    send_ok<A_path_PathBuf>()
    sync_ok<A_path_PathBuf>()
    // process::Child
    any_ok<A_process_Child>()
    borrow_ok<A_process_Child>()
    from_ok<A_process_Child>()
    tryfrom_ok<A_process_Child>()
    tryinto_ok<A_process_Child>()
    into_ok<A_process_Child>()
    send_ok<A_process_Child>()
    sync_ok<A_process_Child>()
    // process::Command
    any_ok<A_process_Command>()
    borrow_ok<A_process_Command>()
    from_ok<A_process_Command>()
    tryfrom_ok<A_process_Command>()
    tryinto_ok<A_process_Command>()
    into_ok<A_process_Command>()
    send_ok<A_process_Command>()
    sync_ok<A_process_Command>()
    // process::ExitStatus
    any_ok<A_process_ExitStatus>()
    borrow_ok<A_process_ExitStatus>()
    from_ok<A_process_ExitStatus>()
    tryfrom_ok<A_process_ExitStatus>()
    tryinto_ok<A_process_ExitStatus>()
    into_ok<A_process_ExitStatus>()
    send_ok<A_process_ExitStatus>()
    sync_ok<A_process_ExitStatus>()
    // process::Output
    any_ok<A_process_Output>()
    borrow_ok<A_process_Output>()
    from_ok<A_process_Output>()
    tryfrom_ok<A_process_Output>()
    tryinto_ok<A_process_Output>()
    into_ok<A_process_Output>()
    send_ok<A_process_Output>()
    sync_ok<A_process_Output>()
    // process::Stdio
    any_ok<A_process_Stdio>()
    borrow_ok<A_process_Stdio>()
    from_ok<A_process_Stdio>()
    tryfrom_ok<A_process_Stdio>()
    tryinto_ok<A_process_Stdio>()
    into_ok<A_process_Stdio>()
    send_ok<A_process_Stdio>()
    sync_ok<A_process_Stdio>()
    // gap net::IpAddr ToOwned: no Clone implementation
    // gap net::Ipv4Addr ToOwned: no Clone implementation
    // gap net::Ipv6Addr ToOwned: no Clone implementation
    // gap net::SocketAddr ToOwned: no Clone implementation
    // gap path::PathBuf ToOwned: no Clone implementation
    // gap process::ExitStatus ToOwned: no Clone implementation
    // gap process::ExitStatus ToString: no Display implementation
    // gap process::Output ToOwned: no Clone implementation
    0
}
