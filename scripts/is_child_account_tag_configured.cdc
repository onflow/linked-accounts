import ChildAccount from "../contracts/ChildAccount.cdc"

/// This script allows one to determine if a given account has a
/// ChildAccountTag configured
///
pub fun main(child: Address): Bool {

    // Return whether the ChildAccountTagPublic is configured as a test of whether
    // the ChildAccountTag is configured at the given address
    return getAccount(parent).getCapability<
            &ChildAccount.ChildAccountTag{ChildAccount.ChildAccountTagPublic}
        >(ChildAccount.ChildAccountTagPublicPath).check()
}
 