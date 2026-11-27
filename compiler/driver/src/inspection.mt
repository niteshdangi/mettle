import alloc.vec.new
import mettle_syntax.inspect.{ Inspection, InspectionNode }
import std.io.{ Error, Writer }

pub parent fn write_json_text(mut out: Writer, read bytes: [u8], format_piece: bool): Unit throws Error {
    let hex = b"0123456789abcdef"
    var start = 0usize
    var index = 0usize
    var escaped = false
    while index < bytes.len() {
        let byte = bytes[index]
        if format_piece && !escaped && (byte == b'{' || byte == b'}') {
            let paired = index + 1usize < bytes.len() && bytes[index + 1usize] == byte
            if paired || byte == b'}' {
                let end = if paired { index + 1usize } else { index }
                try out.write_all(read bytes[start..end])
                index += if paired { 2usize } else { 1usize }
                start = index
                continue
            }
        }
        escaped = byte == b'\\' && !escaped
        if byte == b'"' || byte == b'\\' || byte < 32u8 {
            try out.write_all(read bytes[start..index])
            let spelling = match byte {
                b'"' => present(b'"'), b'\\' => present(b'\\'),
                b'\n' => present(b'n'), b'\r' => present(b'r'), b'\t' => present(b't'),
                _ => none
            }
            if let present(code) = spelling {
                try out.write_all([b'\\', code])
            } else {
                try out.write_all([b'\\', b'u', b'0', b'0',
                    hex[(byte >> 4u8) as usize], hex[(byte & 15u8) as usize]])
            }
            start = index + 1usize
        }
        index += 1usize
    }
    try out.write_all(read bytes[start..])
}

fn quoted(mut out: Writer, read bytes: [u8]): Unit throws Error {
    try out.write_all("\"".as_bytes())
    try write_json_text(mut out, bytes, false)
    try out.write_all("\"".as_bytes())
}

fn indent(mut out: Writer, level: usize): Unit throws Error {
    let spaces = "                                                                ".as_bytes()
    let pairs = spaces.len() / 2usize
    var remaining = level
    while remaining >= pairs {
        try out.write_all(spaces)
        remaining -= pairs
    }
    try out.write_all(read spaces[0usize..remaining * 2usize])
}

fn item(mut out: Writer, level: usize, first: bool): Unit throws Error {
    try out.write_all((if first { "\n" } else { ",\n" }).as_bytes())
    try indent(mut out, level)
}

fn close_array(mut out: Writer, level: usize, nonempty: bool): Unit throws Error {
    if nonempty { try item(mut out, level, true) }
    try out.write_all("]".as_bytes())
}

copy type Frame { node: usize; child: usize }

fn node_head(mut out: Writer, read node: InspectionNode, level: usize): Unit throws Error {
    let begin = node.span.begin
    try out.write_all("{\n".as_bytes())
    try indent(mut out, level + 1usize)
    try out.write_line(f"\"begin\": {begin},")
    try indent(mut out, level + 1usize)
    try out.write_all("\"children\": [".as_bytes())
}

fn node_tail(mut out: Writer, read node: InspectionNode, level: usize): Unit throws Error {
    let end = node.span.end
    let kind = node.kind
    let semicolon = if node.semicolon { "true" } else { "false" }
    try close_array(mut out, level + 1usize, !node.children.is_empty())
    try out.write_all(",\n".as_bytes())
    try indent(mut out, level + 1usize)
    try out.write_line(f"\"end\": {end},")
    try indent(mut out, level + 1usize)
    try out.write_line(f"\"kind\": {kind},")
    try indent(mut out, level + 1usize)
    try out.write_all("\"label\": ".as_bytes())
    try quoted(mut out, node.loop_label.as_slice())
    try out.write_all(",\n".as_bytes())
    try indent(mut out, level + 1usize)
    try out.write_line(f"\"semicolon\": {semicolon},")
    try indent(mut out, level + 1usize)
    try out.write_all("\"text\": ".as_bytes())
    try quoted(mut out, node.text.as_slice())
    try item(mut out, level, true)
    try out.write_all("}".as_bytes())
}

fn write_body(mut out: Writer, read view: Inspection, root: usize): Unit throws Error {
    var stack = new<Frame>()
    try node_head(mut out, read view.nodes[root], 3usize)
    stack.push(Frame(root, 0usize))
    while !stack.is_empty() {
        let index = stack.len() - 1usize
        let frame = stack[index]
        let node = read view.nodes[frame.node]
        let level = 3usize + 2usize * index
        if frame.child == node.children.len() {
            try node_tail(mut out, node, level)
            let _ = stack.pop()
        } else {
            let child = node.children[frame.child]
            stack[index].child += 1usize
            try item(mut out, level + 2usize, frame.child == 0usize)
            try node_head(mut out, read view.nodes[child], level + 2usize)
            stack.push(Frame(child, 0usize))
        }
    }
}

pub fn write_inspection(mut out: Writer, read view: Inspection): Unit throws Error {
    try out.write_all("{\n  \"aliases\": [".as_bytes())
    for index in 0usize..view.aliases.len() {
        let entry = read view.aliases[index]
        try item(mut out, 2usize, index == 0usize)
        try out.write_all("{\n      \"name\": ".as_bytes())
        try quoted(mut out, entry.name.as_slice())
        try out.write_all(",\n      \"target\": ".as_bytes())
        try quoted(mut out, entry.target.as_slice())
        try out.write_all("\n    }".as_bytes())
    }
    try close_array(mut out, 1usize, !view.aliases.is_empty())

    try out.write_all(",\n  \"functions\": [".as_bytes())
    for index in 0usize..view.functions.len() {
        let function = read view.functions[index]
        try item(mut out, 2usize, index == 0usize)
        try out.write_all("{\n      \"body\": ".as_bytes())
        try write_body(mut out, view, function.body)
        try out.write_all(",\n      \"name\": ".as_bytes())
        try quoted(mut out, function.name.as_slice())
        try out.write_all(",\n      \"receiver\": ".as_bytes())
        try quoted(mut out, function.receiver_mode.as_slice())
        try out.write_all("\n    }".as_bytes())
    }
    try close_array(mut out, 1usize, !view.functions.is_empty())

    try out.write_all(",\n  \"products\": [".as_bytes())
    for index in 0usize..view.products.len() {
        let product = read view.products[index]
        let copy_requested = if product.copy_requested { "true" } else { "false" }
        try item(mut out, 2usize, index == 0usize)
        try out.write_all("{\n".as_bytes())
        try out.write_line(f"      \"copy\": {copy_requested},")
        try out.write_all("      \"fields\": [".as_bytes())
        for field_index in 0usize..product.fields.len() {
            let field = read product.fields[field_index]
            try item(mut out, 4usize, field_index == 0usize)
            try out.write_all("{\n          \"name\": ".as_bytes())
            try quoted(mut out, field.name.as_slice())
            try out.write_all(",\n          \"type\": ".as_bytes())
            try quoted(mut out, field.annotation.as_slice())
            try out.write_all("\n        }".as_bytes())
        }
        try close_array(mut out, 3usize, !product.fields.is_empty())
        try out.write_all(",\n      \"name\": ".as_bytes())
        try quoted(mut out, product.name.as_slice())
        try out.write_all("\n    }".as_bytes())
    }
    try close_array(mut out, 1usize, !view.products.is_empty())

    try out.write_all(",\n  \"tokens\": [".as_bytes())
    for index in 0usize..view.tokens.len() {
        let token = read view.tokens[index]
        let begin = token.span.begin
        let end = token.span.end
        let kind = token.kind
        try item(mut out, 2usize, index == 0usize)
        try out.write_all("{\n".as_bytes())
        try out.write_line(f"      \"begin\": {begin},\n      \"end\": {end},\n      \"kind\": {kind},")
        try out.write_all("      \"text\": ".as_bytes())
        try quoted(mut out, token.text.as_slice())
        try out.write_all("\n    }".as_bytes())
    }
    try close_array(mut out, 1usize, !view.tokens.is_empty())
    try out.write_all("\n}\n".as_bytes())
}
