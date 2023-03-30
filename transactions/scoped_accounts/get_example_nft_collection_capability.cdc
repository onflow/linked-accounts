import MetadataViews from "../../contracts/utility/MetadataViews.cdc"
import NonFungibleToken from "../../contracts/utility/NonFungibleToken.cdc"
import ExampleNFT from "../../contracts/utility/ExampleNFT.cdc"
import ScopedAccounts from "../../contracts/ScopedAccounts.cdc"

transaction(accessPointCapStoragePathIdentifier: String) {

    let collectionPublicRef: &ExampleNFT.Collection{NonFungibleToken.CollectionPublic}

    prepare(signer: AuthAccount) {
        let capPath: StoragePath = StoragePath(identifier: accessPointCapStoragePathIdentifier)
            ?? panic("Couldn't construct StoragePath from given identifier: ".concat(accessPointCapStoragePathIdentifier))
        let accessPointCapRef: &Capability<&ScopedAccounts.AccessPoint> = signer.borrow<&Capability<&ScopedAccounts.AccessPoint>>(
            from: capPath
        ) ?? panic("Could not borrow reference to stored AccessPoint Capability!")
        let accessPointRef: &ScopedAccounts.AccessPoint = accessPointCapRef.borrow()
            ?? panic("Could not borrow AccessPoint from stored Capability!")
        let collectionCap: Capability = accessPointRef.getCapabilityByType(
                Type<&ExampleNFT.Collection{ExampleNFT.ExampleNFTCollectionPublic,NonFungibleToken.CollectionPublic,NonFungibleToken.Receiver,MetadataViews.ResolverCollection}>()
            ) ?? panic("Could not retrieve Capability of specified Type from")
        self.collectionPublicRef = collectionCap.borrow<&ExampleNFT.Collection{NonFungibleToken.CollectionPublic}>()
            ?? panic("Problem with retrieved ExampleNFT Collection Capability!")
    }

    execute {
        // Can now do stuff with CollectionPublic reference
        // ...
    }
}
