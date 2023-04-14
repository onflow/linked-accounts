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
pub fun main(address: Address): {Address: LinkedAccountData} {
    let linkedAccountData: {Address: LinkedAccountData} = {}

    // Get reference to ScopedLinkedAccounts.Collection if it exists
    if let collectionRef = getAccount(address).getCapability<&ScopedLinkedAccounts.Collection{ScopedLinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}>(
            ScopedLinkedAccounts.CollectionPublicPath
        ).borrow() {
        let addressToID: {Address: UInt64}  = collectionRef.getAddressToID()
        // Iterate over each linked account in ScopedLinkedAccounts.Collection
        for linkedAccountAddress in addressToID.keys {
            let accountInfo: LinkedAccountMetadataViews.AccountInfo = (collectionRef.borrowViewResolver(
                    id: addressToID[linkedAccountAddress]!
                ).resolveView(
                    Type<LinkedAccountMetadataViews.AccountInfo>()
                ) as! LinkedAccountMetadataViews.AccountInfo?)!
            // Insert the linked account's metadata in each child account indexing on the account's address
            linkedAccountData.insert(
                key: linkedAccountAddress,
                LinkedAccountData(
                    address: linkedAccountAddress,
                    accountInfo: accountInfo
                )
            )
        }
    }
    return linkedAccountData 
}
