@layout(C)
copy type Element { value: i32 }
extern "C" fn first(values: [Element; 65]): i32 { values[0].value }

fn main() {
    if first([Element(42); 65]) == 42 { 0 } else { 1 }
}
