import MetadataViews from "../../contracts/utility/MetadataViews.cdc"
import NonFungibleToken from "../../contracts/utility/NonFungibleToken.cdc"
import ExampleNFT from "../../contracts/utility/ExampleNFT.cdc"
import ScopedAccounts from "../../contracts/ScopedAccounts.cdc"

/// Gets a reference to an ExampleNFT Collection from another account made available in an AccessPoint the signer has
/// access to via a stored Accessor.
///
transaction {

    let collectionPublicRef: &ExampleNFT.Collection{NonFungibleToken.CollectionPublic}

    prepare(signer: AuthAccount) {
        // Get a reference to the stored Accessor
        let accessorRef: &ScopedAccounts.Accessor = signer.borrow<&ScopedAccounts.Accessor>(from: ScopedAccounts.AccessorStoragePath)
            ?? panic("Could not borrow reference to stored Accessor!")
        // Borrow a reference to the wrapped AccessPoint Capability
        let accessPointRef: &ScopedAccounts.AccessPoint = accessorRef.borrowAccessPoint()
        // Get a Capability from the AccessPoint
        let collectionCap: Capability = accessPointRef.getCapabilityByType(
                Type<&ExampleNFT.Collection{ExampleNFT.ExampleNFTCollectionPublic,NonFungibleToken.CollectionPublic,NonFungibleToken.Receiver,MetadataViews.ResolverCollection}>()
            ) ?? panic("Could not retrieve Capability of specified Type from")
        // Borrow a reference from the return generic Capability
        self.collectionPublicRef = collectionCap.borrow<&ExampleNFT.Collection{NonFungibleToken.CollectionPublic}>()
            ?? panic("Problem with retrieved ExampleNFT Collection Capability!")
    }

    execute {
        // Can now do stuff with CollectionPublic reference
        // ...
    }
}
