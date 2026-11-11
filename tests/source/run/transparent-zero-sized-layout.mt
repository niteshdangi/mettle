@layout(transparent)
copy type Empty {}
@layout(transparent)
copy type Marker { first: Unit; second: Unit }
@align(8)
copy type Aligned {}
@layout(transparent)
copy type Wrapped { marker: Unit; value: Aligned }
@layout(transparent)
copy enum Choice { Value(Unit) }

fn main() {
    if core.mem.size_of<Empty>() == 0usize &&
       core.mem.align_of<Empty>() == 1usize &&
       core.mem.size_of<Marker>() == 0usize &&
       core.mem.align_of<Marker>() == 1usize &&
       core.mem.size_of<Wrapped>() == 0usize &&
       core.mem.align_of<Wrapped>() == 8usize &&
       core.mem.size_of<Choice>() == 0usize &&
       core.mem.align_of<Choice>() == 1usize { 0 } else { 1 }
}
