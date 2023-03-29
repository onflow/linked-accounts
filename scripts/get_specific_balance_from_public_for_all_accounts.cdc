import FungibleToken from "../contracts/utility/FungibleToken.cdc"
import FungibleTokenMetadataViews from "../contracts/utility/FungibleTokenMetadataViews.cdc"
import MetadataViews from "../contracts/utility/MetadataViews.cdc"
import LinkedAccounts from "../contracts/LinkedAccounts.cdc"

/// Returns a dictionary of VaultInfo indexed on the Type of Vault
pub fun getVaultBalance(_ address: Address, _ balancePath: PublicPath): UFix64 {
    // Get the account
    let account: PublicAccount = getAccount(address)
    // Attempt to get a reference to the balance Capability
    if let balanceRef: &{FungibleToken.Balance} = account.getCapability<&{FungibleToken.Balance}>(
            balancePath
        ).borrow() {
        // Return the balance
        return balanceRef.balance
    }
    // Vault inaccessible - return 0.0
    return 0.0
}

/// Queries for FT.Vault balance of all FT.Vaults at given path in the specified account and all of its linked accounts
///
/// @param address: Address of the account to query FT.Vault data
///
/// @return A mapping of accounts balances indexed on the associated account address
///
pub fun main(address: Address, balancePath: PublicPath): {Address: UFix64} {
    // Get the balance for the given address
    var balances: {Address: UFix64} = { address: getVaultBalance(address, balancePath) }
    
    /* Iterate over any linked accounts */ 
    //
    // Get reference to LinkedAccounts.Collection if it exists
    if let collectionRef = getAccount(address).getCapability<&LinkedAccounts.Collection{LinkedAccounts.CollectionPublic}>(
            LinkedAccounts.CollectionPublicPath
        ).borrow() {
        // Iterate over each linked account in Collection
        for linkedAccount in collectionRef.getLinkedAccountAddresses() {
            // Add the balance of the linked account address to the running mapping
            balances.insert(key: linkedAccount, getVaultBalance(address, balancePath))
        }
    }
    // Return all balances
    return balances 
}
 