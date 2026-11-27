pub copy enum Scalar { Unit, Bool, I32, U8, U32, U64, Usize }

extend Scalar {
    pub fn integer_width(): u32 {
        match self {
            Scalar.I32 | Scalar.U32 => 32u32,
            Scalar.U8 => 8u32,
            Scalar.U64 | Scalar.Usize => 64u32,
            Scalar.Unit | Scalar.Bool => 0u32
        }
    }
}

extend Scalar {
    pub fn is(other: Scalar): bool { (self as u32) == (other as u32) }
}

pub copy enum PointerAccess { Read, Mut }

pub copy enum FieldType { Scalar(Scalar), ThinPointer(PointerAccess, Scalar) }

pub copy type ObjectLayout {
    pub size: u64
    pub alignment: u64
}

extend FieldType {
    pub fn hosted_layout(): ObjectLayout {
        let size = match self {
            FieldType.ThinPointer(_, _) => 8u64,
            FieldType.Scalar(Scalar.Unit) => 0u64,
            FieldType.Scalar(Scalar.Bool) => 1u64,
            FieldType.Scalar(scalar) => (scalar.integer_width() / 8u32) as u64
        }
        ObjectLayout(size, if size == 0u64 { 1u64 } else { size })
    }
}

pub copy type ProductLayout {
    size: u64
    alignment: u64
}

extend ProductLayout {
    pub static fn new(): ProductLayout { ProductLayout(0u64, 1u64) }

    pub mut fn append(field: FieldType): u64? {
        let layout = field.hosted_layout()
        let offset = align_up(self.size, layout.alignment)
        let alignment = if self.alignment > layout.alignment { self.alignment } else { layout.alignment }
        let size = offset + layout.size
        if align_up(size, alignment) > 9223372036854775807u64 { return none }
        self.size = size
        self.alignment = alignment
        present(offset)
    }

    pub fn finish(): ObjectLayout { ObjectLayout(align_up(self.size, self.alignment), self.alignment) }
}

fn align_up(value: u64, alignment: u64): u64 {
    let mask = alignment - 1u64
    (value + mask) & (18446744073709551615u64 ^ mask)
}
