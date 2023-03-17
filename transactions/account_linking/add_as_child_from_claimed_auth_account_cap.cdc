import MetadataViews from "../../contracts/utility/MetadataViews.cdc"
import NonFungibleToken from "../../contracts/utility/NonFungibleToken.cdc"
import LinkedAccountMetadataViews from "../../contracts/LinkedAccountMetadataViews.cdc"
import LinkedAccounts from "../../contracts/LinkedAccounts.cdc"

/// Signing account claims a Capability to specified Address's AuthAccount
/// and adds it as a child account in its LinkedAccounts.Collection, allowing it 
/// to maintain the claimed Capability
///
transaction(
        linkedAccountAddress: Address,
        linkedAccountName: String,
        linkedAccountDescription: String,
        clientThumbnailURL: String,
        clientExternalURL: String,
        handlerPathSuffix: String
    ) {

    let collectionRef: &LinkedAccounts.Collection
    let info: LinkedAccountMetadataViews.AccountInfo
    let authAccountCap: Capability<&AuthAccount>

    prepare(signer: AuthAccount) {
        /** --- Configure Collection & get ref --- */
        //
        // Check that Collection is saved in storage
        if signer.type(at: LinkedAccounts.CollectionStoragePath) == nil {
            signer.save(
                <-LinkedAccounts.createEmptyCollection(),
                to: LinkedAccounts.CollectionStoragePath
            )
        }
        // Link the public Capability
        if !signer.getCapability<
                &LinkedAccounts.Collection{LinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}
            >(LinkedAccounts.CollectionPublicPath).check() {
            signer.unlink(LinkedAccounts.CollectionPublicPath)
            signer.link<&LinkedAccounts.Collection{LinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}>(
                LinkedAccounts.CollectionPublicPath,
                target: LinkedAccounts.CollectionStoragePath
            )
        }
        // Link the private Capability
        if !signer.getCapability<
                &LinkedAccounts.Collection{LinkedAccounts.CollectionPublic, NonFungibleToken.CollectionPublic, NonFungibleToken.Receiver, NonFungibleToken.Provider, MetadataViews.ResolverCollection}
            >(LinkedAccounts.CollectionPrivatePath).check() {
            signer.unlink(LinkedAccounts.CollectionPrivatePath)
            signer.link<
                &LinkedAccounts.Collection{LinkedAccounts.CollectionPublic, NonFungibleToken.CollectionPublic, NonFungibleToken.Receiver, NonFungibleToken.Provider, MetadataViews.ResolverCollection}
            >(
                LinkedAccounts.CollectionPrivatePath,
                target: LinkedAccounts.CollectionStoragePath
            )
        }
        // Get Collection reference from signer
        self.collectionRef = signer.borrow<
                &LinkedAccounts.Collection
            >(
                from: LinkedAccounts.CollectionStoragePath
            )!
        
        /** --- Prep to link account --- */
        //
        // Claim the previously published AuthAccount Capability from the given Address
        self.authAccountCap = signer.inbox.claim<&AuthAccount>(
                "AuthAccountCapability",
                provider: linkedAccountAddress
            ) ?? panic(
                "No AuthAccount Capability available from given provider"
                .concat(linkedAccountAddress.toString())
                .concat(" with name ")
                .concat("AuthAccountCapability")
            )
        
        /** --- Construct metadata --- */
        //
        // Construct linked account metadata from given arguments
        self.info = LinkedAccountMetadataViews.AccountInfo(
            name: linkedAccountName,
            description: linkedAccountDescription,
            thumbnail: MetadataViews.HTTPFile(url: clientThumbnailURL),
            externalURL: MetadataViews.ExternalURL(clientExternalURL)
        )
    }

    execute {
        // Add account as child to the signer's LinkedAccounts.Collection
        self.collectionRef.addAsChildAccount(
            linkedAccountCap: self.authAccountCap,
            linkedAccountMetadata: self.info,
            linkedAccountMetadataResolver: nil,
            handlerPathSuffix: handlerPathSuffix
        )
    }
}
 