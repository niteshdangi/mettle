module source_helpers;
import core.future.Future

type Source {}
type Sink {}

extend Source {
    async fn write_some(read buf: [u8]): usize {
        let sink = Sink()
        await sink.write_all(buf)
    }

    async fn write_all(read buf: [u8]): usize {
        await self.write_some(buf)
    }
}

extend Sink {
    async fn write_all(read buf: [u8]): usize { buf.len() }
}

fn drive<F: Future<Output = usize>>(take future: F): usize {
    source_helpers.drive!(future)
}

fn main(): i32 {
    let source = Source()
    let bytes = [1u8, 2u8, 3u8]
    if drive(source.write_all(read bytes)) != 3usize { return 1 }
    0
}
