// expect-error: unsafe 2:62 requires an unsafe block
fn main() { let cell=core.cell.UnsafeCell.new(42); let value=cell.get_ref(); *value }
