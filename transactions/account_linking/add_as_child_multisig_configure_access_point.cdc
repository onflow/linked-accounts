#allowAccountLinking

import MetadataViews from "../../contracts/utility/MetadataViews.cdc"
import NonFungibleToken from "../../contracts/utility/NonFungibleToken.cdc"
import LinkedAccountMetadataViews from "../../contracts/LinkedAccountMetadataViews.cdc"
import LinkedAccounts from "../../contracts/LinkedAccounts.cdc"
import ScopedAccounts from "../../contracts/ScopedAccounts.cdc"
import ExampleValidators from "../../contracts/ExampleValidators.cdc"
import ExampleNFT from "../../contracts/utility/ExampleNFT.cdc"

/// Links thie signing accounts as labeled, with the child's AuthAccount Capability maintained in the parent's
/// LinkedAccounts.Collection, ensuring that secondary is scoped by a ScopedAccounts.AccessPoint
///
transaction(
    linkedAccountName: String,
    linkedAccountDescription: String,
    clientThumbnailURL: String,
    clientExternalURL: String,
    parentAuthAccountPathSuffix: String,
    accessPointAuthAccountPathSuffix: String,
    handlerPathSuffix: String,
    accessPointRecipient: Address,
    keyIndexToRevoke: Int
) {

    let collectionRef: &LinkedAccounts.Collection
    let info: LinkedAccountMetadataViews.AccountInfo
    let linkedauthAccountCap: Capability<&AuthAccount>
    let accessPointAuthAccountCap: Capability<&AuthAccount>
    let linkedAccountAddress: Address

    prepare(parent: AuthAccount, child: AuthAccount) {
        pre {
            parentAuthAccountPathSuffix != accessPointAuthAccountPathSuffix:
                "Transaction does not suppot linking AuthAccount Capability to parent & access points on same paths!"
        }
        
        /** --- Configure Collection & get ref --- */
        //
        // Check that Collection is saved in storage
        if parent.type(at: LinkedAccounts.CollectionStoragePath) == nil {
            parent.save(
                <-LinkedAccounts.createEmptyCollection(),
                to: LinkedAccounts.CollectionStoragePath
            )
        }
        // Link the public Capability
        if !parent.getCapability<
                &LinkedAccounts.Collection{NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, LinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}
            >(LinkedAccounts.CollectionPublicPath).check() {
            parent.unlink(LinkedAccounts.CollectionPublicPath)
            parent.link<&LinkedAccounts.Collection{NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, LinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}>(
                LinkedAccounts.CollectionPublicPath,
                target: LinkedAccounts.CollectionStoragePath
            )
        }
        // Link the private Capability
        if !parent.getCapability<
                &LinkedAccounts.Collection{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic, LinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}
            >(LinkedAccounts.CollectionPrivatePath).check() {
            parent.unlink(LinkedAccounts.CollectionPrivatePath)
            parent.link<
                &LinkedAccounts.Collection{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic, LinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}
            >(
                LinkedAccounts.CollectionPrivatePath,
                target: LinkedAccounts.CollectionStoragePath
            )
        }
        // Get Collection reference from parent
        self.collectionRef = parent.borrow<&LinkedAccounts.Collection>(
                from: LinkedAccounts.CollectionStoragePath
            )!

        /* --- Link the child account's AuthAccount Capability & assign --- */
        //
        // Assign the PrivatePath where we'll link the AuthAccount Capability
        let linkedAuthAccountPath: PrivatePath = PrivatePath(identifier: parentAuthAccountPathSuffix)
            ?? panic("Could not construct PrivatePath from given suffix: ".concat(parentAuthAccountPathSuffix))
        // Get the AuthAccount Capability, linking if necessary
        if !child.getCapability<&AuthAccount>(linkedAuthAccountPath).check() {
            // Unlink any Capability that may be there
            child.unlink(linkedAuthAccountPath)
            // Link & assign the AuthAccount Capability
            self.linkedauthAccountCap = child.linkAccount(linkedAuthAccountPath)!
        } else {
            // Assign the AuthAccount Capability
            self.linkedauthAccountCap = child.getCapability<&AuthAccount>(linkedAuthAccountPath)
        }
        self.linkedAccountAddress = self.linkedauthAccountCap.borrow()?.address ?? panic("Problem with retrieved AuthAccount Capability")

        /** --- Construct metadata --- */
        //
        // Construct linked account metadata from given arguments
        self.info = LinkedAccountMetadataViews.AccountInfo(
            name: linkedAccountName,
            description: linkedAccountDescription,
            thumbnail: MetadataViews.HTTPFile(url: clientThumbnailURL),
            externalURL: MetadataViews.ExternalURL(clientExternalURL)
        )

        /* --- Configure AccessPoint in child account --- */
        //
        // Assign the PrivatePath where we'll link the AuthAccount Capability
        let accessPointAuthAccountPath: PrivatePath = PrivatePath(identifier: accessPointAuthAccountPathSuffix)
            ?? panic("Could not construct PrivatePath from given suffix: ".concat(accessPointAuthAccountPathSuffix))
        // Get the AuthAccount Capability, linking if necessary
        if !child.getCapability<&AuthAccount>(accessPointAuthAccountPath).check() {
            // Unlink any Capability that may be there
            child.unlink(accessPointAuthAccountPath)
            // Link & assign the AuthAccount Capability
            self.accessPointAuthAccountCap = child.linkAccount(accessPointAuthAccountPath)!
        } else {
            // Assign the AuthAccount Capability
            self.accessPointAuthAccountCap = child.getCapability<&AuthAccount>(accessPointAuthAccountPath)
        }

        // Define allowable Types and Paths to retrieve them - those listed below are just for illustration, you'd want
        // to define the types and paths for your specific use case & ensure that the account is configured with those
        // Capabilities
        let allowedCapabilities: {Type: CapabilityPath} = {
            Type<&ExampleNFT.Collection{ExampleNFT.ExampleNFTCollectionPublic,NonFungibleToken.CollectionPublic,NonFungibleToken.Receiver,MetadataViews.ResolverCollection}>(): ExampleNFT.CollectionPublicPath,
            Type<&ExampleNFT.Collection{ExampleNFT.ExampleNFTCollectionPublic,NonFungibleToken.CollectionPublic,NonFungibleToken.Provider,MetadataViews.ResolverCollection}>(): /private/exampleNFTCollection
        }
        // Make sure nothing is currently stored at the expected path
        assert(child.type(at: ScopedAccounts.AccessPointStoragePath) == nil, message: "Object already stored at path: ".concat(ScopedAccounts.AccessPointStoragePath.toString()))
        // Create & save AccessPoint in the signing child account
        child.save(
                <-ScopedAccounts.createAccessPoint(
                    authAccountCapability: self.accessPointAuthAccountCap,
                    allowedCapabilities: allowedCapabilities,
                    validator: ExampleValidators.ExampleNFTCollectionValidator()
                ),
                to: ScopedAccounts.AccessPointStoragePath
            )
        // Link the AccessPointPublic Capability in public
        child.link<&ScopedAccounts.AccessPoint{ScopedAccounts.AccessPointPublic}>(ScopedAccounts.AccessPointPublicPath, target: ScopedAccounts.AccessPointStoragePath)
        // Link the AccessPoint Capability in private
        child.link<&ScopedAccounts.AccessPoint>(ScopedAccounts.AccessPointPrivatePath, target: ScopedAccounts.AccessPointStoragePath)
        // Get & assign the AccessPoint Capability
        let accessPointCap: Capability<&ScopedAccounts.AccessPoint> = child.getCapability<&ScopedAccounts.AccessPoint>(ScopedAccounts.AccessPointPrivatePath)

        /* Ensure scoped access is delegated & remove key access */
        //
        // Publish AccessPoint Capability for declared recipient
        child.inbox.publish(accessPointCap, name: "AccessPoint", recipient: accessPointRecipient)
        // Revoke the specified key on the account, so the dapp no longer has control of the child account
        if child.keys.get(keyIndex: keyIndexToRevoke) != nil {
            child.keys.revoke(keyIndex: keyIndexToRevoke)
        }
    }

    execute {
        // Add child account if it's parent-child accounts aren't already linked
        if !self.collectionRef.getLinkedAccountAddresses().contains(self.linkedAccountAddress) {
            // Add the child account
            self.collectionRef.addAsChildAccount(
                linkedAccountCap: self.linkedauthAccountCap,
                linkedAccountMetadata: self.info,
                linkedAccountMetadataResolver: nil,
                handlerPathSuffix: handlerPathSuffix
            )
        }
    }

    post {
        self.collectionRef.getLinkedAccountAddresses().contains(self.linkedAccountAddress):
            "Problem linking accounts!"
    }
}
