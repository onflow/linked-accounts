import MetadataViews from "../contracts/utility/MetadataViews.cdc"
import NonFungibleToken from "../contracts/utility/NonFungibleToken.cdc"
import ScopedLinkedAccounts from "../contracts/ScopedLinkedAccounts.cdc"

/// This script allows one to determine if a given account has a ScopedLinkedAccounts.Collection configured as expected
///
/// @param address: The address to query against
///
/// @return True if the account has a ScopedLinkedAccounts.Collection configured at the canonical path, false otherwise
///
pub fun main(address: Address): Bool {
    // Get the account
    let account = getAuthAccount(address)
    // Get the Collection's Metadata
    let collectionView: MetadataViews.NFTCollectionData = (ScopedLinkedAccounts.resolveView(Type<MetadataViews.NFTCollectionData>()) as! MetadataViews.NFTCollectionData?)!
    // Assign public & private capabilities from expected paths
    let collectionPublicCap = account.getCapability<&ScopedLinkedAccounts.Collection{NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, ScopedLinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}>(
            collectionView.publicPath
        )
    let collectionPrivateCap = account.getCapability<&ScopedLinkedAccounts.Collection{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic, ScopedLinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}>(
            collectionView.providerPath
        )
    
    // Return whether account is configured as expected
    return account.type(at: collectionView.storagePath) == Type<@ScopedLinkedAccounts.Collection>() && collectionPublicCap.check() && collectionPrivateCap.check()
}