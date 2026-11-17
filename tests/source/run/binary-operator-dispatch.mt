fn integers(left: i32, right: i32): bool {
    left + right == 10 && left - right == 4 && left * right == 21 &&
    left / right == 2 && left % right == 1 &&
    (left & right) == 3 && (left | right) == 7 && (left ^ right) == 4 &&
    (left << right) == 56 && (left >> right) == 0 &&
    left > right && left >= right && right < left && right <= left &&
    left != right && left == left
}

fn negatives(left: i32, right: i32): bool {
    left / right == -2 && left % right == -1 && (left >> right) == -1 &&
    left < right && left <= right && right > left && right >= left
}

fn floating(left: f64, right: f64): bool {
    left + right == 9.0 && left - right == 5.0 && left * right == 14.0 &&
    left / right == 3.5 && left % right == 1.0 &&
    left > right && left >= right && right < left && right <= left &&
    left != right && left == left
}

fn units(left: Unit, right: Unit): bool {
    left == right && left <= right && left >= right &&
    !(left != right) && !(left < right) && !(left > right)
}

fn main() {
    if integers(7, 3) && negatives(-7, 3) &&
       floating(7.0, 2.0) && units((),()) { 0 } else { 1 }
}
