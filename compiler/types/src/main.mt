pub copy enum Scalar { Unit, Bool, I32 }

extend Scalar {
    pub fn is(other: Scalar): bool { (self as u32) == (other as u32) }
}
