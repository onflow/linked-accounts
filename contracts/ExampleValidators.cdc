import NonFungibleToken from "./utility/NonFungibleToken.cdc"
import MetadataViews from "./utility/MetadataViews.cdc"
import ExampleNFT from "./utility/ExampleNFT.cdc"
import ScopedLinkedAccounts from "./ScopedLinkedAccounts.cdc"

/// A contract containing example ScopedAccounts.CapabilityValidator implementations
///
pub contract ExampleValidators {

    /// An example CapabilityValidator specific to ExampleNFT Capabilities
    pub struct ExampleNFTCollectionValidator : ScopedLinkedAccounts.CapabilityValidator {
        /// An array of Types this validator will validate as true
        access(self) let allowedTypes: [Type]

        init() {
            self.allowedTypes = [
                Type<&ExampleNFT.Collection{ExampleNFT.ExampleNFTCollectionPublic,NonFungibleToken.CollectionPublic,NonFungibleToken.Receiver,MetadataViews.ResolverCollection}>(),
                Type<&ExampleNFT.Collection{ExampleNFT.ExampleNFTCollectionPublic,NonFungibleToken.CollectionPublic,NonFungibleToken.Provider,MetadataViews.ResolverCollection}>()
            ]
        }

        /// Getter for the types allowed by this validator
        ///
        pub fun getAllowedTypes(): [Type] {
            return self.allowedTypes
        }
        
        /// Returns true if the given Capability resolves to an allowed Type and it matches the expected Type
        ///
        pub fun validate(expectedType: Type, capability: Capability): Bool {
            let actualType: Type = capability.borrow<&AnyResource>().getType()
            return actualType == expectedType && self.allowedTypes.contains(actualType)
        }
    }
}
 