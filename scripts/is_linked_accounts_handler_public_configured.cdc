import ScopedLinkedAccounts from "../contracts/ScopedLinkedAccounts.cdc"

/// This script allows one to determine if a given account has a ScopedLinkedAccounts.AccessPoint configured properly
///
/// @param address: The address to query against
///
/// @return True if the account has a ScopedLinkedAccounts.AccessPointPublic configured at the canonical paths, false otherwise
///
pub fun main(address: Address): Bool {

    // Get a AccessPointPublic Capability at the specified address
    let accessPointPublicCap = getAccount(address).getCapability<
            &ScopedLinkedAccounts.AccessPoint{ScopedLinkedAccounts.AccessPointPublic}
        >(ScopedLinkedAccounts.AccessPointPublicPath)

    // Determine if the AccessPoint is stored as expected & public Capability is valid
    return getAuthAccount(address).type(at: ScopedLinkedAccounts.AccessPointStoragePath) == Type<@ScopedLinkedAccounts.AccessPoint>() &&
        accessPointPublicCap.check()
}
 