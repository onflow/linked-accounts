import ScopedLinkedAccounts from "../contracts/ScopedLinkedAccounts.cdc"

/// Returns the allowed Capabilities scoped in an AccessPoint from a ScopedLinkedAccounts.AccessPointPublic
///
pub fun main(accessPointAddress: Address): {Type: CapabilityPath} {
    // Borrow reference to AccessPointPublic at specified Address
    let accessPointPublicRef = getAccount(accessPointAddress).getCapability<&ScopedLinkedAccounts.AccessPoint{ScopedLinkedAccounts.AccessPointPublic}>(
        ScopedLinkedAccounts.AccessPointPublicPath
    ).borrow()
    ?? panic("Could not get reference to AccessPointPublic!")
    // Return the allowed Capabilities
    return accessPointPublicRef.getAllowedCapabilities()
}