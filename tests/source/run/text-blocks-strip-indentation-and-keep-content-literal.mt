fn main(): i32 {
    let block = """
        first "quoted" \n stays
          indented\t

        last {x} \u{41} """
        """
    if block != "first \"quoted\" \\n stays\n  indented\\t\n\nlast {x} \\u{41} \"\"\"" { return 1 }
    let flush = """
  keep
"""
    if flush != "  keep" { return 2 }
    let empty = """
    """
    if !empty.is_empty() { return 3 }
    let sized = """
        a
        b
        """.len()
    if sized != 3usize { return 4 }
    0
}
