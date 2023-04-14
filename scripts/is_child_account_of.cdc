import ScopedLinkedAccounts from "../contracts/ScopedLinkedAccounts.cdc"

/// This script allows one to determine if a given account is linked as a child account of the specified parent account
/// as the link is defined by the ScopedLinkedAccounts contract
///
pub fun main(parent: Address, child: Address): Bool {

    // Get a reference to the ScopedLinkedAccounts.Collection in parent's account
    if let collectionRef = getAccount(parent).getCapability<&ScopedLinkedAccounts.Collection{ScopedLinkedAccounts.CollectionPublic}>(
            ScopedLinkedAccounts.CollectionPublicPath
        ).borrow() {
        // Check if the link is active between accounts
        collectionRef.isLinkActive(onAddress: child)
    }
    
    return false
}
 