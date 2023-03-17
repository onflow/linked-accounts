import LinkedAccounts from "../contracts/LinkedAccounts.cdc"

/// Returns the types of Capabilities a linked account has been granted via its LinkedAccounts.Handler.
///
/// @param address: The account address to query against
///
/// @return An array of Capability Types the account has been granted via Collection -> Handler granting funnel
///         or nil if the given account does not have a HandlerPublic Capability configured.
pub fun main(address: Address): [Type]? {

    // Get a ref to the LinkedAccounts.Handler if possible
    if let handlerRef = getAccount(address).getCapability<
            &LinkedAccounts.Handler{LinkedAccounts.HandlerPublic}
        >(LinkedAccounts.HandlerPublicPath).borrow() {
        // Return its granted types
        return handlerRef.getGrantedCapabilityTypes()
    }
    return nil
}
