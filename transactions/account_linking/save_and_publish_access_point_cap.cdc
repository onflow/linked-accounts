#allowAccountLinking

import MetadataViews from "../../contracts/utility/MetadataViews.cdc"
import NonFungibleToken from "../../contracts/utility/NonFungibleToken.cdc"
import LinkedAccountMetadataViews from "../../contracts/LinkedAccountMetadataViews.cdc"
import ScopedLinkedAccounts from "../../contracts/ScopedLinkedAccounts.cdc"
import ExampleValidators from "../../contracts/ExampleValidators.cdc"
import ExampleNFT from "../../contracts/utility/ExampleNFT.cdc"

/// Signing account publishes a Capability to its AuthAccount for
/// the specified parentAddress to claim
///
transaction(
    linkedAccountName: String,
    linkedAccountDescription: String,
    clientThumbnailURL: String,
    clientExternalURL: String,
    authAccountPathSuffix: String,
    parentAddress: Address
) {

    let authAccountCap: Capability<&AuthAccount>

    prepare(admin: AuthAccount, child: AuthAccount) {
        /** --- Link child AuthAccount Capability --- */
        //
        // Assign the PrivatePath where we'll link the AuthAccount Capability
        let authAccountPath: PrivatePath = PrivatePath(identifier: authAccountPathSuffix)
            ?? panic("Could not construct PrivatePath from given suffix: ".concat(authAccountPathSuffix))
        // Get the AuthAccount Capability, linking if necessary
        if !child.getCapability<&AuthAccount>(authAccountPath).check() {
            child.unlink(authAccountPath)
            self.authAccountCap = child.linkAccount(authAccountPath)!
        } else {
            self.authAccountCap = child.getCapability<&AuthAccount>(authAccountPath)
        }

        /** --- Construct metadata for AccessPoint in child account --- */
        //
        // Construct linked account metadata from given arguments
        let info = LinkedAccountMetadataViews.AccountInfo(
            name: linkedAccountName,
            description: linkedAccountDescription,
            thumbnail: MetadataViews.HTTPFile(url: clientThumbnailURL),
            externalURL: MetadataViews.ExternalURL(clientExternalURL)
        )

        // Define allowable Types and Paths to retrieve them - those listed below are just for illustration, you'd want
        // to define the types and paths for your specific use case & ensure that the account is configured with those
        // Capabilities
        let allowedCapabilities: {Type: CapabilityPath} = {
            Type<@ExampleNFT.Collection{ExampleNFT.ExampleNFTCollectionPublic,NonFungibleToken.CollectionPublic,NonFungibleToken.Receiver,MetadataViews.ResolverCollection}>(): ExampleNFT.CollectionPublicPath,
            Type<@ExampleNFT.Collection{ExampleNFT.ExampleNFTCollectionPublic,NonFungibleToken.CollectionPublic,NonFungibleToken.Provider,MetadataViews.ResolverCollection}>(): /private/exampleNFTCollection
        }

        /** --- Get an AccessPointAdmin reference --- */
        //
        // Get AccessPointAdmin resource from admin
        if admin.type(at: ScopedLinkedAccounts.AccessPointAdminStoragePath) == nil {
            admin.save(<-ScopedLinkedAccounts.createAccessPointAdmin(), to: ScopedLinkedAccounts.AccessPointAdminStoragePath)
        }
        let adminRef = admin.borrow<&ScopedLinkedAccounts.AccessPointAdmin>(from: ScopedLinkedAccounts.AccessPointAdminStoragePath)!

        // Make sure nothing is currently stored at the expected path
        assert(child.type(at: ScopedLinkedAccounts.AccessPointStoragePath) == nil, message: "Object already stored at path: ".concat(ScopedLinkedAccounts.AccessPointStoragePath.toString()))
        // Create & save AccessPoint in the signing child account
        child.save(
                <-adminRef.createAccessPoint(
                    authAccountCapability: self.authAccountCap,
                    allowedCapabilities: allowedCapabilities,
                    validator: ExampleValidators.ExampleNFTCollectionValidator(),
                    parentAddress: parentAddress,
                    metadata: info,
                    resolver: nil
                ),
                to: ScopedLinkedAccounts.AccessPointStoragePath
            )
        // Link the AccessPointPublic Capability in public
        child.link<&ScopedLinkedAccounts.AccessPoint{ScopedLinkedAccounts.AccessPointPublic}>(ScopedLinkedAccounts.AccessPointPublicPath, target: ScopedLinkedAccounts.AccessPointStoragePath)
        // Link the AccessPoint Capability in private
        child.link<&ScopedLinkedAccounts.AccessPoint>(ScopedLinkedAccounts.AccessPointPrivatePath, target: ScopedLinkedAccounts.AccessPointStoragePath)
        // Get & assign the AccessPoint Capability
        let accessPointCap = child.getCapability<&ScopedLinkedAccounts.AccessPoint>(ScopedLinkedAccounts.AccessPointPrivatePath)

        // Publish for the specified Address
        child.inbox.publish(accessPointCap, name: "AccessPointCapability", recipient: parentAddress)
    }
}