import LinkedAccounts from "../contracts/LinkedAccounts.cdc"

/// Returns an array containing all of an account's linked account addresses or nil if a LinkedAccounts.Collectioon
/// is not configured.
///
pub fun main(address: Address): [Address]? {
    if let linkedAccountsCollectionRef = getAccount(address).getCapability<&LinkedAccounts.Collection{LinkedAccounts.CollectionPublic}>(
            LinkedAccounts.CollectionPublicPath
        ).borrow() {
        return linkedAccountsCollectionRef.getLinkedAccountAddresses()
    }
    return nil
}