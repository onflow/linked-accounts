import LinkedAccounts from "../contracts/LinkedAccounts.cdc"

/// This script returns whether the LinkedAccounts.Handler at the given address (if one exists) maintains a
/// Capability of specified Type.
/// 
/// @param address: The address of the account to query against
/// @param capabilityType: The Type of Capability the caller requests to know if the given account has in its 
///         LinkedAccounts.Handler
///
/// @return A value of `false` denotes that either the address does not have a Handler Capability 
/// configured or it does and has not been granted a Capability of given Type.
///
pub fun main(address: Address, capabilityType: Type): Bool {
    // Get a reference to the given account's HandlerPublic Capability
    if let handlerRef = getAccount(address).getCapability<&LinkedAccounts.Handler{LinkedAccounts.HandlerPublic}
        >(LinkedAccounts.HandlerPublicPath).borrow() {
        // Check if tag has been granted Capability of specified type
        return handlerRef.getGrantedCapabilityTypes().contains(capabilityType)
    }
    return false
}
 