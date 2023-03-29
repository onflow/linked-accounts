import NonFungibleToken from "../../contracts/utility/NonFungibleToken.cdc"
import ViewResolver from "../../contracts/utility/ViewResolver.cdc"
import MetadataViews from "../../contracts/utility/MetadataViews.cdc"
import LinkedAccountMetadataViews from "../../contracts/LinkedAccountMetadataViews.cdc"
import LinkedAccounts from "../../contracts/LinkedAccounts.cdc"

/// Sets up a LinkedAccounts.Collection in signer's account to enable management of linked accounts via
/// AuthAccount Capabilities wrapped in NFTs
///
transaction {
    prepare(signer: AuthAccount) {
        // Check that Collection is saved in storage
        if signer.type(at: LinkedAccounts.CollectionStoragePath) == nil {
            signer.save(
                <-LinkedAccounts.createEmptyCollection(),
                to: LinkedAccounts.CollectionStoragePath
            )
        }
        // Link the public Capability
        if !signer.getCapability<
                &LinkedAccounts.Collection{NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, LinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}
            >(LinkedAccounts.CollectionPublicPath).check() {
            signer.unlink(LinkedAccounts.CollectionPublicPath)
            signer.link<&LinkedAccounts.Collection{NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, LinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}>(
                LinkedAccounts.CollectionPublicPath,
                target: LinkedAccounts.CollectionStoragePath
            )
        }
        // Link the private Capability
        if !signer.getCapability<
                &LinkedAccounts.Collection{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic, LinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}
            >(LinkedAccounts.CollectionPrivatePath).check() {
            signer.unlink(LinkedAccounts.CollectionPrivatePath)
            signer.link<
                &LinkedAccounts.Collection{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic, LinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}
            >(
                LinkedAccounts.CollectionPrivatePath,
                target: LinkedAccounts.CollectionStoragePath
            )
        }
    }
}
