import ScopedLinkedAccounts from "../contracts/ScopedLinkedAccounts.cdc"

/// Returns the allowed Capabilities scoped in an AccessPoint from a ScopedLinkedAccounts.Collection
///
pub fun main(address: Address): {Address: {Type: CapabilityPath}}  {
    // Init a return value
    let allowedCapabilities: {Address: {Type: CapabilityPath}} = {}
    
    // Get a reference to a ScopedLinkedAccounts.Collection
    if let collectionRef = getAccount(address).getCapability<&ScopedLinkedAccounts.Collection{ScopedLinkedAccounts.CollectionPublic}>(
            ScopedLinkedAccounts.CollectionPublicPath
        ).borrow() {
        // Get all linked account addresses
        let linkedAddresses: [Address] = collectionRef.getLinkedAccountAddresses()
        // Iterate over each
        for linkedAddress in linkedAddresses {
            // Get a reference to the account's AccessPoint
            if let accessPointRef = collectionRef.borrowAccessPointPublic(address: linkedAddress) {
                // Insert the allowed Capabilities into our return value
                allowedCapabilities.insert(key: linkedAddress, accessPointRef.getAllowedCapabilities())
            }
        }
    }
    
    // Return the final aggregate value
    return allowedCapabilities
}
