fn first<T: Copy>(read values: [T; 65]): T { values[0] }

fn access<T: Copy + Unpin, const N: usize>(
    mut value: pinned mut [T; N]): mut [T; N] from value {
    value.get_mut()
}

interface Ready {}
extend i32 implements Ready {}
copy type Wrapper<T: Copy> {
    value: T
    marker: core.marker.PhantomPinned
}
unsafe extend<T: Copy + Ready> Wrapper<T> implements Unpin {}

fn conditional<T: Copy + Ready>(mut values: [Wrapper<T>; 65]): mut [Wrapper<T>; 65] from values {
    var handle = core.pin.Pin.new(mut values)
    handle.into_inner()
}

fn main() {
    var values = [21; 65]
    {
        var handle = core.pin.Pin.new(mut values)
        access(handle)[0] += 21
    }
    var wrapped = [Wrapper(40,core.marker.PhantomPinned); 65]
    conditional(wrapped)[0].value += 2
    if first(values) == 42 && values[64] == 21 &&
       wrapped[0].value == 42 && wrapped[64].value == 40 { 0 } else { 1 }
}
