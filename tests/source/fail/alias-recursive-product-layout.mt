// expect-error-count: 1
// expect-error: type 4:13 recursive by-value
alias Link = Node
type Node { next: Link }
fn main() { 0 }
