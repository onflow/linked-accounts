import ScopedLinkedAccounts from "../contracts/ScopedLinkedAccounts.cdc"

/// Returns the allowed Capabilities scoped in an AccessPoint from a ScopedLinkedAccounts.Collection
///
pub fun main(address: Address, linkedAddress: Address): {Type: CapabilityPath}?  {
    if let collectionRef = getAccount(address).getCapability<&ScopedLinkedAccounts.Collection{ScopedLinkedAccounts.CollectionPublic}>(
            ScopedLinkedAccounts.CollectionPublicPath
        ).borrow() {
        return collectionRef.borrowAccessPointPublic(address: address)?.getAllowedCapabilities() ?? nil
    }
    return nil
}
 