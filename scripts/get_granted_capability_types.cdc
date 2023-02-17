import ChildAccount from "../contracts/ChildAccount.cdc"

/// Returns the types a child account has been granted via
/// its ChildAccountTag
///
pub fun main(childAddress: Address): [Type]? {

    // Get a ref to the ChildAccountTagPublic if possible
    if let tagRef = getAccount(childAddress).getCapability<
            &ChildAccount.ChildAccountTag{ChildAccount.ChildAccountTagPublic}
        >(ChildAccount.ChildAccountTagPublicPath).borrow() {

        return tagRef.getGrantedCapabilityTypes()
    }

    return nil
}
