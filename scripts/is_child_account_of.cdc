import LinkedAccounts from "../contracts/LinkedAccounts.cdc"

/// This script allows one to determine if a given account is linked as a child account of the specified parent account
/// as the link is defined by the LinkedAccounts contract
///
pub fun main(parent: Address, child: Address): Bool {

    // Get a reference to the LinkedAccounts.Collection in parent's account
    if let collectionRef = getAccount(parent).getCapability<&LinkedAccounts.Collection{LinkedAccounts.CollectionPublic}>(
            LinkedAccounts.CollectionPublicPath
        ).borrow() {
        // Check if the link is active between accounts
        return collectionRef.isLinkActive(onAddress: child)
    }
    return false
}
 