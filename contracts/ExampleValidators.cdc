import NonFungibleToken from "./utility/NonFungibleToken.cdc"
import MetadataViews from "./utility/MetadataViews.cdc"
import ExampleNFT from "./utility/ExampleNFT.cdc"
import ScopedAccounts from "./ScopedAccounts.cdc"

/// A contract containing example ScopedAccounts.CapabilityValidator implementations
///
pub contract ExampleValidators {

    /// An example Validator. Implementers would likely want to further restrict the expected types on a specific
    /// Collection implementation (e.g. &ExampleNFT.Collection{NonFungibleToken.Provider})
    pub struct ExampleNFTCollectionValidator : ScopedAccounts.CapabilityValidator {
        pub fun validate(expectedType: Type, capability: Capability): Bool {
            switch expectedType {
                case Type<&ExampleNFT.Collection{ExampleNFT.ExampleNFTCollectionPublic,NonFungibleToken.CollectionPublic,NonFungibleToken.Receiver,MetadataViews.ResolverCollection}>():
                    return capability.borrow<&ExampleNFT.Collection{ExampleNFT.ExampleNFTCollectionPublic,NonFungibleToken.CollectionPublic,NonFungibleToken.Receiver,MetadataViews.ResolverCollection}>() != nil
                case Type<&ExampleNFT.Collection{ExampleNFT.ExampleNFTCollectionPublic,NonFungibleToken.CollectionPublic,NonFungibleToken.Provider,MetadataViews.ResolverCollection}>():
                    return capability.borrow<&ExampleNFT.Collection{ExampleNFT.ExampleNFTCollectionPublic,NonFungibleToken.CollectionPublic,NonFungibleToken.Provider,MetadataViews.ResolverCollection}>() != nil
                default:
                    return false
            }
        }
    }
}
 