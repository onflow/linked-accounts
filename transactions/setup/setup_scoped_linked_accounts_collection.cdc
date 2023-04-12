import NonFungibleToken from "../../contracts/utility/NonFungibleToken.cdc"
import ViewResolver from "../../contracts/utility/ViewResolver.cdc"
import MetadataViews from "../../contracts/utility/MetadataViews.cdc"
import LinkedAccountMetadataViews from "../../contracts/LinkedAccountMetadataViews.cdc"
import ScopedLinkedAccounts from "../../contracts/ScopedLinkedAccounts.cdc"

/// Sets up a LinkedAccounts.Collection in signer's account to enable management of linked accounts via
/// AuthAccount Capabilities wrapped in NFTs
///
transaction {
    prepare(signer: AuthAccount) {
        // Check that Collection is saved in storage
        if signer.type(at: ScopedLinkedAccounts.CollectionStoragePath) == nil {
            signer.save(
                <-ScopedLinkedAccounts.createEmptyCollection(),
                to: ScopedLinkedAccounts.CollectionStoragePath
            )
        }
        // Link the public Capability
        if !signer.getCapability<
                &ScopedLinkedAccounts.Collection{NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, ScopedLinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}
            >(ScopedLinkedAccounts.CollectionPublicPath).check() {
            signer.unlink(ScopedLinkedAccounts.CollectionPublicPath)
            signer.link<&ScopedLinkedAccounts.Collection{NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, ScopedLinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}>(
                ScopedLinkedAccounts.CollectionPublicPath,
                target: ScopedLinkedAccounts.CollectionStoragePath
            )
        }
        // Link the private Capability
        if !signer.getCapability<
                &ScopedLinkedAccounts.Collection{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic, ScopedLinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}
            >(ScopedLinkedAccounts.CollectionPrivatePath).check() {
            signer.unlink(ScopedLinkedAccounts.CollectionPrivatePath)
            signer.link<
                &ScopedLinkedAccounts.Collection{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic, ScopedLinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}
            >(
                ScopedLinkedAccounts.CollectionPrivatePath,
                target: ScopedLinkedAccounts.CollectionStoragePath
            )
        }
    }
}
