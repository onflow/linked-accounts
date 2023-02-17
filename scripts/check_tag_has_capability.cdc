import ChildAccount from "../contracts/ChildAccount.cdc"

/// This script returns whether the ChildAccountTag at the given address 
/// maintains a Capability of specified Type.
/// A value of `false` denotes that either the address does not have a
/// ChildAccountTagPublic Capability configured or it does and has not
/// been granted a Capability of given Type.
///
pub fun main(address: Address, capabilityType: Type): Bool {
    // Get a reference to the ChildAccountTagPublic Capability
    if let tagRef = getAccount(address).getCapability<
            &ChildAccount.ChildAccountTag{ChildAccount.ChildAccountTagPublic}
        >(ChildAccount.ChildAccountTagPublicPath).borrow() {
        // Check if tag has been granted Capability of specified type
        return tagRef.getGrantedCapabilityTypes().contains(capabilityType)
    }
    return false
}
 