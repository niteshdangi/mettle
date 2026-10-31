// expect-stdout: async net echo ok\n
import std.task
import std.net.{AsyncTcpListener, SocketAddr}
import std.io.Writer
import std.time.from_millis
import core.future.{Context, Future, Poll}

async fn echo(listener: AsyncTcpListener, count: i32): i32 {
    var served = 0
    while served < count {
        let accepted = await listener.accept()
        let pair = match take accepted {
            success(value) => value,
            failure(_) => { return 1 }
        }
        let stream = pair.0
        var buffer = [0u8; 32]
        let received = await stream.read_some(buffer)
        let size = match take received {
            success(value) => value,
            failure(_) => { return 2 }
        }
        let sent = await stream.write_all(buffer.split_at(size).0)
        match take sent {
            success(_) => {},
            failure(_) => { return 3 }
        }
        served += 1
    }
    0
}

async fn client(addr: SocketAddr, value: u8): i32 {
    let connected = await std.net.async_tcp_connect(addr)
    let stream = match take connected {
        success(value) => value,
        failure(_) => { return 10 }
    }
    var bytes = [value; 1]
    let sent = await stream.write_all(bytes)
    match take sent {
        success(_) => {},
        failure(_) => { return 11 }
    }
    var reply = [0u8; 1]
    let received = await stream.read_some(reply)
    let size = match take received {
        success(value) => value,
        failure(_) => { return 12 }
    }
    if size != 1usize || reply[0usize] != value { return 13 }
    0
}

type AcceptTimeout<F> {
    operation: F
    timer: task.Sleep
}

extend<F: Future> AcceptTimeout<F> implements Future {
    type Output = bool
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<bool> {
        // The parent stays pinned, so neither polled field is moved afterward.
        let me = unsafe { self.get_unchecked_mut() }
        let operation = unsafe {
            core.pin.Pin.new_unchecked(mut me.operation).poll(mut cx)
        }
        match take operation {
            Poll.Ready(_) => { return Poll.Ready(false) },
            Poll.Pending => {}
        }
        let timer = unsafe {
            core.pin.Pin.new_unchecked(mut me.timer).poll(mut cx)
        }
        match take timer {
            Poll.Ready(()) => Poll.Ready(true),
            Poll.Pending => Poll.Pending
        }
    }
}

fn accept_timeout<F: Future>(operation: take F, duration: std.time.Duration): AcceptTimeout<F> {
    AcceptTimeout(operation, task.sleep(duration))
}

fn main(): i32 {
    let bound = capture std.net.async_tcp_listen(
        std.net.socket_addr(std.net.localhost(), 0u16)
    )
    var listener = match take bound {
        success(value) => value,
        failure(_) => { return 20 }
    }
    let address = match take capture listener.local_addr() {
        success(value) => value,
        failure(_) => { return 21 }
    }

    // The timer wins; dropping the still-pending accept must unregister it.
    if !task.block_on(accept_timeout(listener.accept(), from_millis(5u64))) {
        return 22
    }

    let executor = task.executor()
    let server = executor.spawn(echo(listener, 4))
    let first = executor.spawn(client(address, 31u8))
    let second = executor.spawn(client(address, 47u8))
    let third = executor.spawn(client(address, 83u8))
    let fourth = executor.spawn(client(address, 109u8))
    executor.run()
    match take capture server.join() {
        success(code) => if code != 0 { return 23 },
        failure(_) => { return 24 }
    }
    match take capture first.join() {
        success(code) => if code != 0 { return 25 },
        failure(_) => { return 26 }
    }
    match take capture second.join() {
        success(code) => if code != 0 { return 27 },
        failure(_) => { return 28 }
    }
    match take capture third.join() {
        success(code) => if code != 0 { return 29 },
        failure(_) => { return 30 }
    }
    match take capture fourth.join() {
        success(code) => if code != 0 { return 31 },
        failure(_) => { return 32 }
    }

    var output = std.io.stdout()
    match take capture output.write_all("async net echo ok\n".as_bytes()) {
        success(_) => {},
        failure(_) => { return 34 }
    }
    0
}
