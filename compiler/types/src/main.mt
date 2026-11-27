pub copy enum Scalar { Unit, Bool, I32, U8, U32, Usize }

extend Scalar {
    pub fn integer_width(): u32 {
        match self {
            Scalar.I32 | Scalar.U32 => 32u32,
            Scalar.U8 => 8u32,
            Scalar.Usize => 64u32,
            Scalar.Unit | Scalar.Bool => 0u32
        }
    }
}

extend Scalar {
    pub fn is(other: Scalar): bool { (self as u32) == (other as u32) }
}
