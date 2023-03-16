import LinkedAccounts from "../contracts/LinkedAccounts.cdc"

/// This script allows one to determine if a given account has a LinkedAccounts.Handler configured properly
///
/// @param address: The address to query against
///
/// @return True if the account has a LinkedAccounts.HandlerPublic configured at the canonical paths, false otherwise
///
pub fun main(address: Address): Bool {

    // Get a HandlerPublic Capability at the specified address
    let handlerPublicCap = getAccount(address).getCapability<
            &LinkedAccounts.Handler{LinkedAccounts.HandlerPublic}
        >(LinkedAccounts.HandlerPublicPath)

    // Determine if the Handler is stored as expected & public Capability is valid
    return getAuthAccount(address).type(at: LinkedAccounts.HandlerStoragePath) == Type<@LinkedAccounts.Handler>() &&
        handlerPublicCap.check()
}
 