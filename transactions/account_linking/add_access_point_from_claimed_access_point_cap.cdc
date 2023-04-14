import MetadataViews from "../../contracts/utility/MetadataViews.cdc"
import NonFungibleToken from "../../contracts/utility/NonFungibleToken.cdc"
import LinkedAccountMetadataViews from "../../contracts/LinkedAccountMetadataViews.cdc"
import ScopedLinkedAccounts from "../../contracts/ScopedLinkedAccounts.cdc"

/// Signing account claims an AccessPoint Capability on specified Address's account and adds it as a linked account in
///  its LinkedAccounts.Collection, allowing it to maintain the claimed Capability.
///
transaction(linkedAccountAddress: Address) {

    let collectionRef: &ScopedLinkedAccounts.Collection
    let accessPointCap: Capability<&ScopedLinkedAccounts.AccessPoint>

    prepare(signer: AuthAccount) {
        /** --- Configure Collection & get ref --- */
        //
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
        // Get Collection reference from signer
        self.collectionRef = signer.borrow<&ScopedLinkedAccounts.Collection>(
                from: ScopedLinkedAccounts.CollectionStoragePath
            )!
        
        /** --- Prep to link account --- */
        //
        // Claim the previously published AuthAccount Capability from the given Address
        self.accessPointCap = signer.inbox.claim<&ScopedLinkedAccounts.AccessPoint>(
                "AccessPointCapability",
                provider: linkedAccountAddress
            ) ?? panic(
                "No AccessPoint Capability available from given provider"
                .concat(linkedAccountAddress.toString())
                .concat(" with name ")
                .concat("AccessPointCapability")
            )
    }

    execute {
        // Add account as child to the signer's ScopedLinkedAccounts.Collection
        self.collectionRef.addAccessPoint(accessPointCap: self.accessPointCap)
    }
}
 