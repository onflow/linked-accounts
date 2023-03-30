import NonFungibleToken from "./utility/NonFungibleToken.cdc"
import MetadataViews from "./utility/MetadataViews.cdc"
import ScopedAccounts from "./ScopedAccounts.cdc"

/// A contract containing example ScopedAccounts.CapabilityValidator implementations
///
pub contract ExampleValidators {

    /// An example Validator. Implementers would likely want to further restrict the expected types on a specific
    /// Collection implementation (e.g. &ExampleNFT.Collection{NonFungibleToken.Provider})
    pub struct NFTCollectionValidator : ScopedAccounts.CapabilityValidator {
        pub fun validate(expectedType: Type, capability: Capability): Bool {
            switch expectedType {
                case Type<&{NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, MetadataViews.ResolverCollection}>():
                    return capability.borrow<&{NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, MetadataViews.ResolverCollection}>() != nil
                case Type<&{NonFungibleToken.Provider}>():
                    return capability.borrow<&{NonFungibleToken.Provider}>() != nil
                case Type<&{MetadataViews.ResolverCollection}>():
                    return capability.borrow<&{MetadataViews.ResolverCollection}>() != nil
                default:
                    return false
            }
        }
    }
}