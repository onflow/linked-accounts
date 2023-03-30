import NonFungibleToken from "../../contracts/utility/NonFungibleToken.cdc"
import ExampleNFT from "../../contracts/utility/ExampleNFT.cdc"
import MetadataViews from "../../contracts/utility/MetadataViews.cdc"

/// This transaction is what an account would run
/// to set itself up to receive NFTs
transaction {

    prepare(signer: AuthAccount) {
        // Return early is resource already stored
        if signer.type(at: ExampleNFT.CollectionStoragePath) != nil {
            return
        }
        // Save Collection
        signer.save(<-ExampleNFT.createEmptyCollection(), to: ExampleNFT.CollectionStoragePath)
        // Link public Capability
        signer.link<&ExampleNFT.Collection{ExampleNFT.ExampleNFTCollectionPublic,NonFungibleToken.CollectionPublic,NonFungibleToken.Receiver,MetadataViews.ResolverCollection}>(
            ExampleNFT.CollectionPublicPath,
            target: ExampleNFT.CollectionStoragePath
        )
        // Link public Capability
        signer.link<&ExampleNFT.Collection{ExampleNFT.ExampleNFTCollectionPublic,NonFungibleToken.CollectionPublic,NonFungibleToken.Provider,MetadataViews.ResolverCollection}>(
            /private/exampleNFTCollection,
            target: ExampleNFT.CollectionStoragePath
        )
    }
}
