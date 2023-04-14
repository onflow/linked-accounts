#allowAccountLinking

import MetadataViews from "../../contracts/utility/MetadataViews.cdc"
import NonFungibleToken from "../../contracts/utility/NonFungibleToken.cdc"
import LinkedAccountMetadataViews from "../../contracts/LinkedAccountMetadataViews.cdc"
import ScopedLinkedAccounts from "../../contracts/ScopedLinkedAccounts.cdc"
import ExampleValidators from "../../contracts/ExampleValidators.cdc"
import ExampleNFT from "../../contracts/utility/ExampleNFT.cdc"

/// Links thie signing accounts as labeled, with the child's AuthAccount Capability maintained in the parent's
/// ScopedLinkedAccounts.Collection, ensuring that secondary is scoped by a ScopedAccounts.AccessPoint
///
transaction(
    linkedAccountName: String,
    linkedAccountDescription: String,
    clientThumbnailURL: String,
    clientExternalURL: String,
    authAccountPathSuffix: String
) {

    let collectionRef: &ScopedLinkedAccounts.Collection
    let info: LinkedAccountMetadataViews.AccountInfo
    let authAccountCap: Capability<&AuthAccount>
    let linkedAccountAddress: Address
    let accessPointCap: Capability<&ScopedLinkedAccounts.AccessPoint>

    prepare(parent: AuthAccount, child: AuthAccount, admin: AuthAccount) {
        
        /** --- Configure Collection & get ref --- */
        //
        // Check that Collection is saved in storage
        if parent.type(at: ScopedLinkedAccounts.CollectionStoragePath) == nil {
            parent.save(
                <-ScopedLinkedAccounts.createEmptyCollection(),
                to: ScopedLinkedAccounts.CollectionStoragePath
            )
        }
        // Link the public Capability
        if !parent.getCapability<
                &ScopedLinkedAccounts.Collection{NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, ScopedLinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}
            >(ScopedLinkedAccounts.CollectionPublicPath).check() {
            parent.unlink(ScopedLinkedAccounts.CollectionPublicPath)
            parent.link<&ScopedLinkedAccounts.Collection{NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, ScopedLinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}>(
                ScopedLinkedAccounts.CollectionPublicPath,
                target: ScopedLinkedAccounts.CollectionStoragePath
            )
        }
        // Link the private Capability
        if !parent.getCapability<
                &ScopedLinkedAccounts.Collection{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic, ScopedLinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}
            >(ScopedLinkedAccounts.CollectionPrivatePath).check() {
            parent.unlink(ScopedLinkedAccounts.CollectionPrivatePath)
            parent.link<
                &ScopedLinkedAccounts.Collection{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic, ScopedLinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}
            >(
                ScopedLinkedAccounts.CollectionPrivatePath,
                target: ScopedLinkedAccounts.CollectionStoragePath
            )
        }
        // Get Collection reference from parent
        self.collectionRef = parent.borrow<&ScopedLinkedAccounts.Collection>(
                from: ScopedLinkedAccounts.CollectionStoragePath
            )!

        /* --- Link the child account's AuthAccount Capability & assign --- */
        //
        // Assign the PrivatePath where we'll link the AuthAccount Capability
        let authAccountPrivatePath: PrivatePath = PrivatePath(identifier: authAccountPathSuffix)
            ?? panic("Could not construct PrivatePath from given suffix: ".concat(authAccountPathSuffix))
        // Get the AuthAccount Capability, linking if necessary
        if !child.getCapability<&AuthAccount>(authAccountPrivatePath).check() {
            // Unlink any Capability that may be there
            child.unlink(authAccountPrivatePath)
            // Link & assign the AuthAccount Capability
            self.authAccountCap = child.linkAccount(authAccountPrivatePath)!
        } else {
            // Assign the AuthAccount Capability
            self.authAccountCap = child.getCapability<&AuthAccount>(authAccountPrivatePath)
        }
        self.linkedAccountAddress = self.authAccountCap.borrow()?.address ?? panic("Problem with retrieved AuthAccount Capability")

        /** --- Construct metadata for AccessPoint in child account --- */
        //
        // Construct linked account metadata from given arguments
        self.info = LinkedAccountMetadataViews.AccountInfo(
            name: linkedAccountName,
            description: linkedAccountDescription,
            thumbnail: MetadataViews.HTTPFile(url: clientThumbnailURL),
            externalURL: MetadataViews.ExternalURL(clientExternalURL)
        )

        /** --- Get an AccessPointAdmin reference --- */
        //
        // Get AccessPointAdmin resource from admin
        if admin.type(at: ScopedLinkedAccounts.AccessPointAdminStoragePath) == nil {
            admin.save(<-ScopedLinkedAccounts.createAccessPointAdmin(), to: ScopedLinkedAccounts.AccessPointAdminStoragePath)
        }
        let adminRef = admin.borrow<&ScopedLinkedAccounts.AccessPointAdmin>(from: ScopedLinkedAccounts.AccessPointAdminStoragePath)!

        // Define allowable Types and Paths to retrieve them - those listed below are just for illustration, you'd want
        // to define the types and paths for your specific use case & ensure that the account is configured with those
        // Capabilities
        let allowedCapabilities: {Type: CapabilityPath} = {
            Type<@ExampleNFT.Collection{ExampleNFT.ExampleNFTCollectionPublic,NonFungibleToken.CollectionPublic,NonFungibleToken.Receiver,MetadataViews.ResolverCollection}>(): ExampleNFT.CollectionPublicPath,
            Type<@ExampleNFT.Collection{ExampleNFT.ExampleNFTCollectionPublic,NonFungibleToken.CollectionPublic,NonFungibleToken.Provider,MetadataViews.ResolverCollection}>(): /private/exampleNFTCollection
        }
        // Make sure nothing is currently stored at the expected path
        assert(child.type(at: ScopedLinkedAccounts.AccessPointStoragePath) == nil, message: "Object already stored at path: ".concat(ScopedLinkedAccounts.AccessPointStoragePath.toString()))
        // Create & save AccessPoint in the signing child account
        child.save(
                <-adminRef.createAccessPoint(
                    authAccountCapability: self.authAccountCap,
                    allowedCapabilities: allowedCapabilities,
                    validator: ExampleValidators.ExampleNFTCollectionValidator(),
                    parentAddress: parent.address,
                    metadata: self.info,
                    resolver: nil
                ),
                to: ScopedLinkedAccounts.AccessPointStoragePath
            )
        // Link the AccessPointPublic Capability in public
        child.link<&ScopedLinkedAccounts.AccessPoint{ScopedLinkedAccounts.AccessPointPublic}>(ScopedLinkedAccounts.AccessPointPublicPath, target: ScopedLinkedAccounts.AccessPointStoragePath)
        // Link the AccessPoint Capability in private
        child.link<&ScopedLinkedAccounts.AccessPoint>(ScopedLinkedAccounts.AccessPointPrivatePath, target: ScopedLinkedAccounts.AccessPointStoragePath)
        // Get & assign the AccessPoint Capability
        self.accessPointCap = child.getCapability<&ScopedLinkedAccounts.AccessPoint>(ScopedLinkedAccounts.AccessPointPrivatePath)
    }

    execute {
        // Add the child account
        self.collectionRef.addAccessPoint(accessPointCap: self.accessPointCap)
    }

    post {
        self.collectionRef.getLinkedAccountAddresses().contains(self.linkedAccountAddress):
            "Problem linking accounts!"
    }
}
