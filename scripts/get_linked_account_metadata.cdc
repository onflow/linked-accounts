import NonFungibleToken from "../contracts/utility/NonFungibleToken.cdc"
import MetadataViews from "../contracts/utility/MetadataViews.cdc"
import LinkedAccountMetadataViews from "../contracts/LinkedAccountMetadataViews.cdc"
import ScopedLinkedAccounts from "../contracts/ScopedLinkedAccounts.cdc"

pub struct LinkedAccountData {
    pub let address: Address
    pub let name: String
    pub let description: String
    pub let creationTimestamp: UFix64
    pub let thumbnail: AnyStruct{MetadataViews.File}
    pub let externalURL: MetadataViews.ExternalURL

    init(
        address: Address,
        accountInfo: LinkedAccountMetadataViews.AccountInfo
    ) {
        self.address = address
        self.name = accountInfo.name
        self.description = accountInfo.description
        self.creationTimestamp = accountInfo.creationTimestamp
        self.thumbnail = accountInfo.thumbnail
        self.externalURL = accountInfo.externalURL
    }
}

/// Returns a mapping of metadata about linked accounts indexed on the account's Address
///
/// @param address: The main account to query against
///
/// @return A mapping of metadata about all the given account's linked accounts, indexed on each linked account's address
///
pub fun main(parent: Address, child: Address): LinkedAccountData? {

    // Get reference to ScopedLinkedAccounts.Collection if it exists
    if let collectionRef = getAccount(parent).getCapability<&ScopedLinkedAccounts.Collection{ScopedLinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}>(
            ScopedLinkedAccounts.CollectionPublicPath
        ).borrow() {
        let addressToID: {Address: UInt64}  = collectionRef.getAddressToID()
        // Iterate over each linked account in ScopedLinkedAccounts.Collection
        let accountInfo: LinkedAccountMetadataViews.AccountInfo = (collectionRef.borrowViewResolverFromAddress(
                address: child
            ).resolveView(
                Type<LinkedAccountMetadataViews.AccountInfo>()
            ) as! LinkedAccountMetadataViews.AccountInfo?)!
        // Unwrap AccountInfo into LinkedAccountData & add address
        return LinkedAccountData(
                address: child,
                accountInfo: accountInfo
            )
    }
    return nil 
}
 