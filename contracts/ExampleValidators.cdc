import NonFungibleToken from "./utility/NonFungibleToken.cdc"
import MetadataViews from "./utility/MetadataViews.cdc"
import ExampleNFT from "./utility/ExampleNFT.cdc"
import ScopedLinkedAccounts from "./ScopedLinkedAccounts.cdc"

/// A contract containing example ScopedAccounts.CapabilityValidator implementations
///
pub contract ExampleValidators {

    /// An example CapabilityValidator enabling allowed Types on init
    ///
    pub struct GenericValidator : ScopedLinkedAccounts.CapabilityValidator {
        /// An array of Types this validator will validate as true
        access(self) let allowedTypes: [Type]

        init(allowedTypes: [Type]) {
            self.allowedTypes =  allowedTypes
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

    /// An example CapabilityValidator validating any instance of NFT Capability
    ///
    pub struct GenericNFTCollectionValidator {
        pub let allowedTypes: [Type]
        init() {
            self.allowedTypes = [Type<@NonFungibleToken.Collection>()]
        }
        /// Getter for the types allowed by this validator
        ///
        pub fun getAllowedTypes(): [Type] {
            return self.allowedTypes
        }
        
        /// Returns true if the given Capability resolves to an allowed Type and it matches the expected Type
        ///
        pub fun validate(expectedType: Type, capability: Capability): Bool {
            // Get a reference from the given Capability
            if let ref = capability.borrow<&AnyResource>() {
                // Retrieve the Type it references
                let actualType: Type = ref.getType()
                // Ensure that the type referenced is allowed and that it is an instance of the expected Type
                return (Type<@NonFungibleToken.Collection>().isSubtype(of: actualType) || ref.isInstance(Type<@NonFungibleToken.Collection>())) &&
                    ref.isInstance(expectedType)
            }
            return false
        }

        access(self) fun checkIsSubtype(_ given: Type): Bool {
            for type in self.allowedTypes {
                if type.isSubtype(of: type) {
                    return true
                }
            }
            return false
        }
    }

    /// An example CapabilityValidator specific to ExampleNFT Capabilities
    ///
    pub struct ExampleNFTCollectionValidator : ScopedLinkedAccounts.CapabilityValidator {
        /// An array of Types this validator will validate as true
        access(self) let allowedTypes: [Type]

        init() {
            self.allowedTypes = [
                Type<@ExampleNFT.Collection{ExampleNFT.ExampleNFTCollectionPublic,NonFungibleToken.CollectionPublic,NonFungibleToken.Receiver,MetadataViews.ResolverCollection}>(),
                Type<@ExampleNFT.Collection{ExampleNFT.ExampleNFTCollectionPublic,NonFungibleToken.CollectionPublic,NonFungibleToken.Provider,MetadataViews.ResolverCollection}>()
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
 