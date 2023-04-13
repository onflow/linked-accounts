import ScopedLinkedAccounts from "../contracts/ScopedLinkedAccounts.cdc"

/// Returns the allowed Capabilities scoped in an AccessPoint
///
pub fun main(address: Address, linkedAddress: Address): {Type: CapabilityPath}?  {
    if let collectionRef = getAccount(address).getCapability<&ScopedLinkedAccounts.Collection{ScopedLinkedAccounts.CollectionPublic}>(
            ScopedLinkedAccounts.CollectionPublicPath
        ).borrow() {
        if let accessPointRef = collectionRef.borrowAccessPointPublic(address: linkedAddress) {
            return accessPointRef.getAllowedCapabilities()
        }
    }
    return nil
}