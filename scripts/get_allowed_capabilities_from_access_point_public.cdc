import ScopedLinkedAccounts from "../contracts/ScopedAccounts.cdc"

/// Returns the allowed Capabilities scoped in an AccessPoint
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