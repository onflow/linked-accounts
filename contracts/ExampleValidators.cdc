import ScopedAccounts from "./ScopedAccounts.cdc"

pub contract ExampleValidators {

    pub struct interface NFTCollectionValidator : ScopedAccounts.CapabilityValidator {
        pub fun validate(expectedType: Type, capability: Capability): Bool {
            switch expectedType {
                case Type<&NonFungibleToken.Collection{NonFungibleToken.Collection}>():
                    if let ref = capability.borrow<&NonFungibleToken.Collection{NonFungibleToken.CollectionPublic}>() {
                        return true
                    }
            }
            return false
        }
    }
}