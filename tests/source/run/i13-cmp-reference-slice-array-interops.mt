import core.cmp.{Ordering, PartialEq, PartialOrd}
import core.text.Text

copy type Left { value: i32 }
copy type Right { value: i32 }

extend Left implements PartialEq<Right> {
    fn eq(read other: Right): bool { self.value == other.value }
}
extend Left implements PartialOrd<Right> {
    fn partial_cmp(read other: Right): Ordering? {
        self.value.partial_cmp(read other.value)
    }
}

fn compare_read_views<region left_region, region right_region>(
    read left: Left from left_region,
    read right: Right from right_region
): bool {
    left == right &&
        left.partial_cmp(right) == present(Ordering.Equal)
}

fn compare_mut_views<region left_region, region right_region>(
    mut left: Left from left_region,
    mut right: Right from right_region
): bool {
    left == right
}

fn compare_read_mut_views<region left_region, region right_region>(
    read left: Left from left_region,
    mut right: Right from right_region
): bool {
    left == right
}

fn compare_mut_read_views<region left_region, region right_region>(
    mut left: Left from left_region,
    read right: Right from right_region
): bool {
    left == right
}

fn compare_array_to_slice<region r>(
    left: [Left; 2],
    read right: [Right] from r
): bool {
    left == right
}

fn compare_slice_to_array<region r>(
    read left: [Left] from r,
    right: [Right; 2]
): bool {
    left == right
}

fn compare_slices<region left_region, region right_region>(
    read left: [Left] from left_region,
    read right: [Right] from right_region
): bool {
    left == right
}

fn compare_optional_text<region left_region, region right_region>(
    read left: (read Text from left_region)?,
    read right: (read Text from right_region)?
): bool {
    left == right
}

fn compare_optional_tuple_text<region left_region, region right_region>(
    read left: (usize, read Text from left_region)?,
    read right: (usize, read Text from right_region)?
): bool {
    left == right
}

fn compare_optional_tuple_order(): bool {
    let left: (Left,)? = present((Left(1i32),))
    let right: (Right,)? = present((Right(1i32),))
    left.partial_cmp(right) == present(Ordering.Equal)
}

fn main(): i32 {
    var left = Left(1i32)
    var right = Right(1i32)
    if !compare_read_views(read left, read right) { return 1 }
    if !compare_mut_views(mut left, mut right) { return 2 }
    if !compare_read_mut_views(read left, mut right) { return 3 }
    if !compare_mut_read_views(mut left, read right) { return 4 }

    let left_array = [Left(1i32), Left(2i32)]
    let right_array = [Right(1i32), Right(2i32)]
    if !compare_array_to_slice(left_array, read right_array) { return 5 }
    if !compare_slice_to_array(read left_array, right_array) { return 6 }
    if !compare_slices(read left_array, read right_array) { return 7 }

    let left_text = alloc.string.from_text("same")
    let right_text = alloc.string.from_text("same")
    if !compare_optional_text(present(left_text.as_text()), present(right_text.as_text())) { return 8 }
    if compare_optional_text(present(left_text.as_text()), none) { return 9 }
    if !compare_optional_tuple_text(
        present((1usize, left_text.as_text())),
        present((1usize, right_text.as_text()))
    ) { return 10 }
    if compare_optional_tuple_text(
        present((1usize, left_text.as_text())),
        present((2usize, right_text.as_text()))
    ) { return 11 }
    if !compare_optional_tuple_order() { return 12 }
    0
}
