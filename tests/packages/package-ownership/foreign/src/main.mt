pub interface Foreign {}
extend bool implements Foreign {}
pub type ForeignType {}
pub module relay {
    pub import super.{Foreign, ForeignType}
}
pub type NativeWitness {}
unsafe extend NativeWitness implements Unpin {}
extend NativeWitness not Transferable;
