/***************************************************************************

    For more info on this contract & associated transactions & scripts, see:
    https://github.com/onflow/linked-accounts
    
    To provide feedback, check FLIP #72
    https://github.com/onflow/flips/pull/72

****************************************************************************/

import NonFungibleToken from "./utility/NonFungibleToken.cdc"
import ViewResolver from "./utility/ViewResolver.cdc"
import MetadataViews from "./utility/MetadataViews.cdc"
import LinkedAccountMetadataViews from "./LinkedAccountMetadataViews.cdc"

/// This contract establishes a standard set of resources representing linked account associations, enabling
/// querying of either end of account links as well as management of linked accounts. By leveraging this contract, a
/// new sort of custody is unlocked - Hybrid Custody - enabling the mainstream-friendly walletless onboarding UX on
/// Flow.
///
/// By leveraging existing metadata standards, builders can easily query a Collection's linked accounts, their
/// relevant metadata, etc. With implementation of the NFT standard, Collection owners can easily transfer delegation
/// they wish in a mental model that's familiar and easy to understand.
///
/// Parties wishing to delegate access on an account encapsulate an AuthAccount Capability along with access 
/// access restrictions in an AccessPoint. Creation of AccessPoints is enabled via AccessPointAdmin resources. By
/// creating AccessPoints from these Admin resources, delegators have a path to give delegatees unrestricted access
/// on linked accounts they created if they wish to do so.
///
/// The Collection below allows a main account to add scoped linked accounts. An account is deemed a child of a
/// parent if the parent maintains delegated access on the child account by way of AccessPoint Capability wrapped in an
/// NFT and saved in a Collection. By the constructs defined in this contract, a linked account can be identified by a
/// stored AccessPoint.
///
/// While one generally would not want to share account access with other parties, this can be helpful in a low-stakes
/// environment where the parent account's owner wants to delegate transaction signing to a secondary party, likely a
/// custodial agent who created the delegator account in the first place via walletless onboarding.
/// 
/// This idea was born out of pursuit of a more seamless on-chain gameplay UX where a user could let a game client
/// submit transactions on their behalf without signing over the whole of their primary account, and do so in a way
/// that didn't require a custom Capability.
///
/// With that said, users should bear in mind that any assets in a linked account incur obvious custodial risk, and
/// that it's generally an anti-pattern to pass around AuthAccounts. In this case, a user owns both accounts so they
/// are technically passing an AuthAccount to themselves in calls to resources that reside in their own account, so 
/// it was deemed a valid application of the pattern. That said, a user should be cognizant of the party with key
/// access on the linked account as this pattern requires some degree of trust in the custodial party.
///
pub contract ScopedLinkedAccounts : NonFungibleToken, ViewResolver {

    /// The number of NFTs in existence
    pub var totalSupply: UInt64

    // NFT conforming events
    pub event ContractInitialized()
    pub event Withdraw(id: UInt64, from: Address?)
    pub event Deposit(id: UInt64, to: Address?)
    
    // ScopedLinkedAccounts Events
    pub event MintedNFT(nftID: UInt64, accessPointID: UInt64, child: Address,  parent: Address, allowedTypes: [Type])
    pub event AddedLinkedAccount(child: Address, parent: Address, nftID: UInt64)
    pub event UpdatedAccessPointCapabilityForLinkedAccount(nftID: UInt64, accessPointID: UInt64, parent: Address, child: Address)
    pub event RemovedLinkedAccount(child: Address, parent: Address)
    pub event AccessPointCreated(id: UInt64, address: Address, pendingParent: Address, creator: Address?, allowedCapabilityTypes: [Type])
    pub event CollectionCreated()

    // Canonical paths
    pub let CollectionStoragePath: StoragePath
    pub let CollectionPublicPath: PublicPath
    pub let CollectionPrivatePath: PrivatePath
    pub let AccessPointAdminStoragePath: StoragePath
    pub let AccessPointAdminPrivatePath: PrivatePath
    pub let AccessPointStoragePath: StoragePath
    pub let AccessPointPublicPath: PublicPath
    pub let AccessPointPrivatePath: PrivatePath
    pub let AccessorStoragePath: StoragePath

    /* --- CapabilityValidator --- */
    //
    /// An interface defining a struct that validates that a given generic Capability returns a reference of the 
    /// given expected Type
    ///
    pub struct interface CapabilityValidator {
        pub fun getAllowedTypes(): [Type]
        pub fun validate(expectedType: Type, capability: Capability): Bool
    }

    /* --- AccessPointAdmin --- */
    //
    pub resource AccessPointAdmin {
        /// Unique identifier for this AccessPointAdmin
        access(self) let id: UInt64

        init() {
            self.id = self.uuid
        }

        /// Returns a new AccessPoint with the given args and associating it with this admin by id
        ///
        pub fun createAccessPoint(
            authAccountCapability: Capability<&AuthAccount>,
            allowedCapabilities: {Type: CapabilityPath},
            validator: AnyStruct{CapabilityValidator},
            parentAddress: Address,
            metadata: AnyStruct{LinkedAccountMetadataViews.AccountMetadata},
            resolver: AnyStruct{LinkedAccountMetadataViews.MetadataResolver}?
        ): @AccessPoint {
            let accessPoint <-create AccessPoint(
                adminID: self.id,
                creatorAddress: self.owner?.address ?? panic("AccessPointAdmin must have an owner for AccessPoint auditability!"),
                authAccountCapability: authAccountCapability,
                allowedCapabilities: allowedCapabilities,
                validator: validator,
                parentAddress: parentAddress,
                metadata: metadata,
                resolver: resolver
            )
            emit AccessPointCreated(
                id: accessPoint.getID(),
                address: accessPoint.getScopedAccountAddress(),
                pendingParent: parentAddress,
                creator: self.owner?.address,
                allowedCapabilityTypes: allowedCapabilities.keys
            )
            return <-accessPoint
        }

        /// Unrestricts the access to the AuthAccount Capability wrapped in the AccessPoint. The given referenced 
        /// AccessPoint must have been created by this Admin, the owner of which would presumably be the custodial
        /// party for the account in which the AccessPoint resides.AccountKey
        ///
        /// **NOTE: **Implementers should consider how shared unrestricted access will affect their custodial
        /// regulatory liability.
        ///
        pub fun unrestrict(accessPointRef: &AccessPoint) {
            pre {
                accessPointRef.getAdminID() == self.id:
                    "Given AccessPoint was not created by this Admin - caller does not have authority to unrestrict access!"
            }
            accessPointRef.unrestrict()
        }
    }

    /* --- AccessPoint --- */
    //
    pub resource interface AccessPointPublic {
        pub fun getID(): UInt64
        pub fun getParentAddress(): Address
        pub fun getCreatorAddress(): Address
        pub fun getAllowedCapabilityTypes(): [Type]
        pub fun getAllowedCapabilities(): {Type: CapabilityPath}
        pub fun getScopedAccountAddress(): Address
    }

    /// A wrapper around an AuthAccount Capability which enforces retrieval of specified Types from specified 
    /// CapabilityPaths
    ///
    pub resource AccessPoint : AccessPointPublic, MetadataViews.Resolver {
        /// Unique identifier for this AccessPoint
        access(self) let id: UInt64
        /// ID of the creating AccessPointAdmin
        access(self) let adminID: UInt64
        /// Address of the creating AccessPointAdmin owner - helpful for identifying reputable account creators
        access(self) let creatorAddress: Address
        /// Capability on the account this resources has access to
        access(self) let authAccountCapability: Capability<&AuthAccount>
        /// Defined Capability resolution Types and where to find associated Capability
        access(self) let allowedCapabilities: {Type: CapabilityPath}
        /// Validates retrieved Capability resolves to expected Type
        access(self) let validator: AnyStruct{CapabilityValidator}
        /// Pointer to this account's parent account
        access(self) var parentAddress: Address
        /// Metadata about the purpose of this child account guarantees standard minimum metadata is stored
        /// about linked accounts
        access(self) let metadata: AnyStruct{LinkedAccountMetadataViews.AccountMetadata}
        /// Resolver struct to increase the flexibility, allowing implementers to resolve their own structs
        access(self) let resolver: AnyStruct{LinkedAccountMetadataViews.MetadataResolver}?
        /// Flag denoting whether link to parent is still active
        access(self) var isActive: Bool
        /// Flag denoting whether this AccessPoint has restricted access on its AuthAccount Capability
        access(self) var restricted: Bool

        init(
            adminID: UInt64,
            creatorAddress: Address
            authAccountCapability: Capability<&AuthAccount>,
            allowedCapabilities: {Type: CapabilityPath},
            validator: AnyStruct{CapabilityValidator},
            parentAddress: Address,
            metadata: AnyStruct{LinkedAccountMetadataViews.AccountMetadata},
            resolver: AnyStruct{LinkedAccountMetadataViews.MetadataResolver}?
        ) {
            pre {
                authAccountCapability.check(): "Problem with provided AuthAccount Capability"
            }
            self.id = self.uuid
            self.adminID = adminID
            self.creatorAddress = creatorAddress
            self.authAccountCapability = authAccountCapability
            self.allowedCapabilities = allowedCapabilities
            self.validator = validator
            self.parentAddress = parentAddress
            self.metadata = metadata
            self.resolver = resolver
            self.isActive = true
            self.restricted = true
        }

        /// Getter for this AccessPoint's unique ID value
        ///
        pub fun getID(): UInt64 {
            return self.id
        }

        pub fun getAdminID(): UInt64 {
            return self.adminID
        }
        
        /// Getter for the Types this AccessPoint has access to
        ///
        pub fun getAllowedCapabilityTypes(): [Type] {
            return self.allowedCapabilities.keys
        }

        /// Returns the mapping to allowed Capabilty Types and corresponding paths
        ///
        pub fun getAllowedCapabilities(): {Type: CapabilityPath} {
            return self.allowedCapabilities
        }

        /// Retrieves the address for which this AccessPoint maintains an AuthAccount Capability for
        ///
        pub fun getScopedAccountAddress(): Address {
            return self.borrowAuthAccount().address
        }

        /// Returns a generic Capability from specified path stored in allowedCapabilities mapping given it's indexed
        /// on a corresponding allowedType. The type is enforced by the stored CapabilityValidator assigned in init.
        ///
        pub fun getCapabilityByPath(_ path: CapabilityPath): Capability? {
            if self.allowedCapabilities.values.contains(path) {
                let expectedType: Type = self.allowedCapabilities.keys[
                        self.allowedCapabilities.values.firstIndex(of: path)!
                    ]
                let cap: Capability = self.borrowAuthAccount().getCapability(path)
                if self.validator.validate(expectedType: expectedType, capability: cap) {
                    return cap
                }
            }
            return nil
        }

        /// Returns a generic Capability of specified Type from its corresponding path stored in allowedCapabilities
        /// mapping. The type is enforced by the stored CapabilityValidator assigned in init.
        ///
        pub fun getCapabilityByType(_ type: Type): Capability? {
            if self.allowedCapabilities.containsKey(type) {
                let account: &AuthAccount = self.borrowAuthAccount()
                let cap: Capability = account.getCapability(
                    self.allowedCapabilities[type]!
                )
                if self.validator.validate(expectedType: type, capability: cap) {
                    return cap
                }
            }
            return nil
        }

        /// Returns the metadata view types supported by this AccessPoint
        ///
        /// @return An array of metadata view types
        ///
        pub fun getViews(): [Type] {
            let views: [Type] = []
            if self.resolver != nil {
                views.appendAll(self.resolver!.getViews())
            }
            views.appendAll([
                Type<LinkedAccountMetadataViews.AccountInfo>(),
                Type<MetadataViews.Display>()
            ])
            if self.metadata.getType() != Type<LinkedAccountMetadataViews.AccountInfo>() {
                views.append(self.metadata.getType())
            }
            return views
        }
        
        /// Returns the requested view if supported or nil otherwise
        ///
        /// @param view: The Type of metadata struct requests
        ///
        /// @return The metadata of requested Type if supported and nil otherwise
        ///
        pub fun resolveView(_ view: Type): AnyStruct? {
            switch view {
                case Type<LinkedAccountMetadataViews.AccountInfo>():
                    return LinkedAccountMetadataViews.AccountInfo(
                        name: self.metadata.name,
                        description: self.metadata.description,
                        thumbnail: self.metadata.thumbnail,
                        externalURL: self.metadata.externalURL
                    )
                case Type<MetadataViews.Display>():
                    return MetadataViews.Display(
                        name: self.metadata.name,
                        description: self.metadata.description,
                        thumbnail: self.metadata.thumbnail
                    )
                case self.metadata.getType():
                    return self.metadata
                default:
                    if self.resolver != nil && self.resolver!.getViews().contains(view) {
                        return self.resolver!.resolveView(view)
                    }
                    return nil
            }
        }

        /// Returns the Address of this linked account's parent Collection
        ///
        pub fun getParentAddress(): Address {
            return self.parentAddress
        }

        /// Getter for the Address which created this AccessPoint. This can be helpful for identifying the entity that
        /// created this AccessPoint
        ///
        pub fun getCreatorAddress(): Address {
            return self.creatorAddress
        }
        
        /// Returns the metadata related to this account's association
        ///
        pub fun getAccountMetadata(): AnyStruct{LinkedAccountMetadataViews.AccountMetadata} {
            return self.metadata
        }

        /// Returns the optional resolver contained within this AccessPoint
        ///
        pub fun getResolver(): AnyStruct{LinkedAccountMetadataViews.MetadataResolver}? {
            return self.resolver
        }
        
        /// Returns whether the link between this AccessPoint and its associated Collection is still active - in
        /// practice whether the linked Collection has removed this AccessPoint's Capability
        ///
        pub fun isCurrentlyActive(): Bool {
            return self.isActive
        }

        pub fun isRestricted(): Bool {
            return self.restricted
        }

        pub fun checkAuthAccountCapability(): Bool {
            return self.authAccountCapability.check()
        }

        /// Updates this AccessPoint's parentAddress, occurring whenever a corresponding NFT transfer occurs
        ///
        /// @param newAddress: The Address of the new parent account
        ///
        access(contract) fun updateParentAddress(_ newAddress: Address) {
            self.parentAddress = newAddress
        }

        /// Sets the isActive Bool flag to false
        ///
        access(contract) fun setInactive() {
            self.isActive = false
        }

        access(contract) fun getAuthAccountCapability(): Capability<&AuthAccount> {
            pre {
                !self.restricted: "AccessPoint is restricted to defined allowable Types!"
            }
            return self.authAccountCapability
        }

        access(contract) fun unrestrict() {
            self.restricted = false
        }

        /// Helper method to return a reference the associated AuthAccount
        ///
        access(self) fun borrowAuthAccount(): &AuthAccount {
            return self.authAccountCapability.borrow() ?? panic("Problem with AuthAccount Capability")
        }
    }

    /** --- NFT --- */
    //
    /// Publicly accessible Capability for linked account wrapping resource, protecting the wrapped Capabilities
    /// from public access via reference as implemented in LinkedAccount.NFT
    ///
    pub resource interface NFTPublic {
        pub let id: UInt64
        pub fun checkAccessPointCapability(): Bool
        pub fun getLinkedAccountAddress(): Address
        pub fun borrowAccessPointPublic(): &AccessPoint{AccessPointPublic}
    }

    /// Wrapper for the linked account's metadata and AccessPoint Capabilities implemented as an NFT
    ///
    pub resource NFT : NFTPublic, NonFungibleToken.INFT, MetadataViews.Resolver {
        pub let id: UInt64
        /// The address of the associated linked account
        access(self) let linkedAccountAddress: Address
        /// Capability for the relevant AccessPoint
        access(self) var accessPointCapability: Capability<&AccessPoint>

        init(accessPointCapability: Capability<&AccessPoint>) {
            pre {
                accessPointCapability.borrow() != nil:
                    "Problem with provided AccessPoint Capability"
                accessPointCapability.borrow()!.owner != nil:
                    "Associated AccessPoint does not have an owner!"
                accessPointCapability.address == accessPointCapability.borrow()!.owner!.address:
                    "Addresses among given Capabilities do not match!"
            }
            self.id = self.uuid
            self.linkedAccountAddress = accessPointCapability.borrow()!.getScopedAccountAddress()
            self.accessPointCapability = accessPointCapability
        }

        /// Function that returns all the Metadata Views implemented by an NFT & by extension the relevant AccessPoint
        ///
        /// @return An array of Types defining the implemented views. This value will be used by developers to know
        ///         which parameter to pass to the resolveView() method.
        ///
        pub fun getViews(): [Type] {
            let accessPointRef: &ScopedLinkedAccounts.AccessPoint = self.getAccessPointRef()
            let views: [Type] = accessPointRef.getViews()
            views.appendAll([
                Type<MetadataViews.NFTCollectionData>(),
                Type<MetadataViews.NFTCollectionDisplay>(),
                Type<MetadataViews.NFTView>(),
                Type<MetadataViews.Display>()
            ])
            return views
        }

        /// Function that resolves a metadata view for this ChildAccount.
        ///
        /// @param view: The Type of the desired view.
        ///
        /// @return A struct representing the requested view.
        ///
        pub fun resolveView(_ view: Type): AnyStruct? {
            switch view {
                case Type<MetadataViews.NFTCollectionData>():
                    return ScopedLinkedAccounts.resolveView(view)
                case Type<MetadataViews.NFTCollectionDisplay>():
                    return ScopedLinkedAccounts.resolveView(view)
                case Type<MetadataViews.NFTView>():
                    let accessPointRef = self.getAccessPointRef()
                    let accountInfo = (accessPointRef.resolveView(
                            Type<LinkedAccountMetadataViews.AccountInfo>()) as! LinkedAccountMetadataViews.AccountInfo?
                        )!
                    return MetadataViews.NFTView(
                        id: self.id,
                        uuid: self.uuid,
                        display: accessPointRef.resolveView(Type<MetadataViews.Display>()) as! MetadataViews.Display?,
                        externalURL: accountInfo.externalURL,
                        collectionData: ScopedLinkedAccounts.resolveView(Type<MetadataViews.NFTCollectionData>()) as! MetadataViews.NFTCollectionData?,
                        collectionDisplay: ScopedLinkedAccounts.resolveView(Type<MetadataViews.NFTCollectionDisplay>()) as! MetadataViews.NFTCollectionDisplay?,
                        royalties: nil,
                        traits: MetadataViews.dictToTraits(
                                dict: {
                                    "id": self.id,
                                    "parentAddress": self.owner?.address,
                                    "linkedAddress": self.getLinkedAccountAddress(),
                                    "creationTimestamp": accountInfo.creationTimestamp,
                                    "allowedCapabilities": accessPointRef.getAllowedCapabilities(),
                                    "isRestricted": accessPointRef.isRestricted()
                                },
                                excludedNames: nil
                            )
                    )
                case Type<MetadataViews.Display>():
                    return self.getAccessPointRef().resolveView(Type<MetadataViews.Display>())
                default:
                    let accessPointRef: &ScopedLinkedAccounts.AccessPoint = self.accessPointCapability.borrow()
                    ?? panic("Problem with AccessPoint Capability in this NFT")
                    return accessPointRef.resolveView(view)
            }
        }

        /// Get a reference to the linked AccessPoint resource.
        ///
        pub fun borrowAccessPoint(): &AccessPoint {
            return self.accessPointCapability.borrow() ?? panic("Problem with AccessPoint Capability in NFT!")
        }

        /// Returns a reference to the AccessPoint
        ///
        pub fun getAccessPointRef(): &AccessPoint {
            return self.accessPointCapability.borrow() ?? panic("Problem with ScopedLinkedAccounts.AccessPoint Capability in NFT!")
        }

        /// Returns whether AccessPoint Capability link is currently active
        ///
        /// @return True if the link is active, false otherwise
        ///
        pub fun checkAccessPointCapability(): Bool {
            return self.accessPointCapability.check()
        }

        /// Returns the linked account address this NFT manages a Capability for
        ///
        /// @return the address of the account this NFT has delegated access to
        ///
        pub fun getLinkedAccountAddress(): Address {
            return self.borrowAccessPoint().getScopedAccountAddress()
        }

        /// Returns a reference to the AccessPoint as AccessPointPublic
        ///
        /// @return a reference to the AccessPoint as AccessPointPublic 
        ///
        pub fun borrowAccessPointPublic(): &AccessPoint{AccessPointPublic} {
            return self.accessPointCapability.borrow() ?? panic("Problem with AccessPoint Capability in NFT!")
        }

        /// Updates this NFT's AuthAccount Capability to another for the same account. Useful in the event the
        /// Capability needs to be retargeted
        ///
        /// @param new: The new AuthAccount Capability, but must be for the same account as the current Capability
        ///
        pub fun updateAccessPointCapability(_ newCap: Capability<&AccessPoint>) {
            pre {
                newCap.check(): "Problem with provided Capability"
                newCap.borrow()!.owner != nil:
                    "Associated AccessPoint does not have an owner!"
                newCap.borrow()!.owner!.address == self.linkedAccountAddress &&
                newCap.address == self.linkedAccountAddress:
                    "Provided AuthAccount is not for this NFT's associated account Address!"
            }
            let accessPointID = newCap.borrow()!.getID()
            self.accessPointCapability = newCap
            emit UpdatedAccessPointCapabilityForLinkedAccount(nftID: self.id, accessPointID: accessPointID, parent: self.owner!.address, child: self.linkedAccountAddress)
        }

        pub fun borrowLinkedAuthAccount(): &AuthAccount? {
            return self.borrowAccessPoint().getAuthAccountCapability().borrow()
        }

        /// Updates this NFT's parent address & the parent address of the associated AccessPoint
        ///
        /// @param newAddress: The address of the new parent account
        ///
        access(contract) fun updateParentAddress(_ newAddress: Address) {
            // Pass through to update the parent account in the associated AccessPoint
            self.getAccessPointRef().updateParentAddress(newAddress)
        }
    }

    /** --- Collection --- */
    //
    /// Interface that allows one to view information about the owning account's
    /// linked accounts including the addresses for all linked accounts and information
    /// about specific linked accounts by Address
    ///
    pub resource interface CollectionPublic {
        pub fun getIDs(): [UInt64]
        pub fun getAddressToID(): {Address: UInt64}
        pub fun getLinkedAccountAddresses(): [Address]
        pub fun getIDOfNFTByAddress(address: Address): UInt64?
        pub fun deposit(token: @NonFungibleToken.NFT)
        pub fun isLinkActive(onAddress: Address): Bool
        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT {
            post {
                result.id == id: "The returned reference's ID does not match the requested ID"
            }
        }
        pub fun borrowNFTSafe(id: UInt64): &NonFungibleToken.NFT? {
            post {
                result == nil || result!.id == id: "The returned reference's ID does not match the requested ID"
            }
        }
        pub fun borrowScopedLinkedAccountsNFTPublic(id: UInt64): &ScopedLinkedAccounts.NFT{ScopedLinkedAccounts.NFTPublic}? {
            post {
                (result == nil) || (result?.id == id):
                    "Cannot borrow ExampleNFT reference: the ID of the returned reference is incorrect"
            }
        }
        pub fun borrowAccessPointPublic(address: Address): &{AccessPointPublic}?
        pub fun borrowViewResolverFromAddress(address: Address): &{MetadataViews.Resolver}
    }

    /// A Collection of ScopedLinkedAccounts.NFTs, maintaining all delegated AuthAccount & AccessPoint Capabilities in NFTs.
    /// One NFT (representing delegated account access) per linked account can be maintained in this Collection,
    /// enabling public view Capabilities and owner-related management methods, including removing linked accounts, as
    /// well as granting & revoking Capabilities. 
    /// 
    pub resource Collection : CollectionPublic, NonFungibleToken.Provider, NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, MetadataViews.ResolverCollection {
        /// Mapping of contained LinkedAccount.NFTs as NonFungibleToken.NFTs
        pub var ownedNFTs: @{UInt64: NonFungibleToken.NFT}
        /// Mapping linked account Address to relevant NFT.id
        access(self) let addressToID: {Address: UInt64}
        /// Mapping of pending addresses which can be deposited
        pub let pendingDeposits: {Address: Bool}

        init() {
            self.ownedNFTs <-{}
            self.addressToID = {}
            self.pendingDeposits = {}
        }

        /// Returns the NFT as a Resolver for the specified ID
        ///
        /// @param id: The id of the NFT
        ///
        /// @return A reference to the NFT as a Resolver
        ///
        pub fun borrowViewResolver(id: UInt64): &{MetadataViews.Resolver} {
            let nft = &self.ownedNFTs[id] as auth &NonFungibleToken.NFT?
                ?? panic("Collection does not have NFT with specified ID")
            let castNFT = nft as! &ScopedLinkedAccounts.NFT
            return castNFT as &AnyResource{MetadataViews.Resolver}
        }

        /// Returns the IDs of the NFTs in this Collection
        ///
        /// @return an array of the contained NFT resources
        ///
        pub fun getIDs(): [UInt64] {
            return self.ownedNFTs.keys
        }

        /// Returns a reference to the specified NonFungibleToken.NFT with given ID
        ///
        /// @param id: The id of the requested NonFungibleToken.NFT
        ///
        /// @return The requested NonFungibleToken.NFT, panicking if there is not an NFT with requested id in this
        ///         Collection
        ///
        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT {
            return &self.ownedNFTs[id] as &NonFungibleToken.NFT? ?? panic("Collection does not have NFT with specified ID")
        }

        /// Returns a reference to the specified NonFungibleToken.NFT with given ID or nil
        ///
        /// @param id: The id of the requested NonFungibleToken.NFT
        ///
        /// @return The requested NonFungibleToken.NFT or nil if there is not an NFT with requested id in this
        ///         Collection
        ///
        pub fun borrowNFTSafe(id: UInt64): &NonFungibleToken.NFT? {
            return &self.ownedNFTs[id] as &NonFungibleToken.NFT?
        }
        
        /// Returns a reference to the specified ScopedLinkedAccounts.NFT as NFTPublic with given ID or nil
        ///
        /// @param id: The id of the requested ScopedLinkedAccounts.NFT as NFTPublic
        ///
        /// @return The requested ScopedLinkedAccounts.NFTublic or nil if there is not an NFT with requested id in this
        ///         Collection
        ///
        pub fun borrowScopedLinkedAccountsNFTPublic(id: UInt64): &ScopedLinkedAccounts.NFT{ScopedLinkedAccounts.NFTPublic}? {
            if let nft = &self.ownedNFTs[id] as auth &NonFungibleToken.NFT? {
                let castNFT = nft as! &ScopedLinkedAccounts.NFT
                return castNFT as &ScopedLinkedAccounts.NFT{ScopedLinkedAccounts.NFTPublic}?
            }
            return nil
        }

        /// Returns whether this Collection has an active link for the given address.
        ///
        /// @return True if there is an NFT in this collection associated with the given address that has active
        /// AuthAccount & AccessPoint Capabilities and a AccessPoint in the linked account that is set as active
        ///
        pub fun isLinkActive(onAddress: Address): Bool {
            if let nftRef = self.borrowScopedLinkedAccountNFT(address: onAddress) {
                return nftRef.checkAccessPointCapability() &&
                    nftRef.borrowAccessPoint().checkAuthAccountCapability() &&
                    nftRef.getAccessPointRef().isCurrentlyActive()
            }
            return false
        }

        /// Takes an address and adds it to pendingDeposits which allows it to be deposited.
        /// If the linked account address of the token deposited is not in this dictionary at the time
        /// of deposit, it will panic.
        ///
        /// @param address: The address which should be permitted to be inserted as a linked account
        ///
        pub fun addPendingDeposit(address: Address) {
            self.pendingDeposits.insert(key: address, true)
        }

        /// Takes an address and removes it from pendingDeposits, no longer permitting
        /// child accounts for the specified address to be inserted
        ///
        /// @param address: The address which should no longer be permitted to be inserted as a linked account
        pub fun removePendingDeposit(address: Address) {
            self.pendingDeposits.remove(key: address)
        }

        /// Takes a given NonFungibleToken.NFT and adds it to this Collection's mapping of ownedNFTs, emitting both
        /// Deposit and AddedLinkedAccount since depositing ScopedLinkedAccountsScopedLinkedAccounts.NFT is effectively giving a Collection owner
        /// delegated access to an account
        ///
        /// @param token: NonFungibleToken.NFT to be deposited to this Collection
        ///
        pub fun deposit(token: @NonFungibleToken.NFT) {
            pre {
                !self.ownedNFTs.containsKey(token.id):
                    "Collection already contains NFT with id: ".concat(token.id.toString())
                self.owner!.address != nil:
                    "Cannot transfer LinkedAccount.NFT to unknown party!"
            }
            // Assign scoped variables from ScopedLinkedAccounts.NFT
            let token <- token as! @ScopedLinkedAccounts.NFT
            let ownerAddress: Address = self.owner!.address
            let linkedAccountAddress: Address = token.getLinkedAccountAddress()
            let id: UInt64 = token.id

            // Ensure this collection allows the address of the linked account to be added
            assert(self.pendingDeposits.containsKey(linkedAccountAddress), message: "address of deposited token is not permitted to be added")
            self.removePendingDeposit(address: linkedAccountAddress)

            // Ensure this Collection does not already have a ScopedLinkedAccounts.NFT for this token's account
            assert(
                !self.addressToID.containsKey(linkedAccountAddress),
                message: "Already have delegated access to account address: ".concat(linkedAccountAddress.toString())
            )

            // Update the AccessPoint's parent address
            token.updateParentAddress(ownerAddress)

            // Add the new token to the ownedNFTs & addressToID mappings
            let oldToken <- self.ownedNFTs[id] <- token
            self.addressToID.insert(key: linkedAccountAddress, id)
            destroy oldToken

            // Ensure the NFT has its id associated to the correct linked address
            assert(
                self.addressToID[linkedAccountAddress] == id,
                message: "Problem associating ScopedLinkedAccounts.NFT account Address to NFT.id"
            )

            // Emit events
            emit Deposit(id: id, to: ownerAddress)
            emit AddedLinkedAccount(child: linkedAccountAddress, parent: ownerAddress, nftID: id)
        }
        
        /// Withdraws the ScopedLinkedAccounts.NFT with the given id as a NonFungibleToken.NFT, emitting standard Withdraw
        /// event along with RemovedLinkedAccount event, denoting the delegated access for the account associated with
        /// the NFT has been removed from this Collection
        ///
        /// @param withdrawID: The id of the requested NFT
        ///
        /// @return The requested ScopedLinkedAccounts.NFT as a NonFungibleToken.NFT
        ///
        pub fun withdraw(withdrawID: UInt64): @NonFungibleToken.NFT {
            pre {
                self.ownedNFTs.containsKey(withdrawID):
                    "Collection does not contain NFT with given id: ".concat(withdrawID.toString())
                self.owner!.address != nil:
                    "Cannot withdraw LinkedAccount.NFT from unknown party!"
            }
            post {
                result.id == withdrawID:
                    "Incorrect NFT withdrawn from Collection!"
                !self.ownedNFTs.containsKey(withdrawID):
                    "Collection still contains NFT with requested ID!"
            }
            // Get the token from the ownedNFTs mapping
            let token: @NonFungibleToken.NFT <- self.ownedNFTs.remove(key: withdrawID)!

            // Get the Address associated with the withdrawing token id
            let linkedAddress: Address = self.addressToID.keys[
                    self.addressToID.values.firstIndex(of: withdrawID)!
                ]
            // Remove the address entry in our secondary mapping
            self.addressToID.remove(key: linkedAddress)!

            // Emit events & return
            emit Withdraw(id: token.id, from: self.owner?.address)
            emit RemovedLinkedAccount(child: linkedAddress, parent: self.owner!.address)
            return <-token
        }

        /// Withdraws the ScopedLinkedAccounts.NFT with the given Address as a NonFungibleToken.NFT, emitting standard 
        /// Withdraw event along with RemovedLinkedAccount event, denoting the delegated access for the account
        /// associated with the NFT has been removed from this Collection
        ///
        /// @param address: The Address associated with the requested NFT
        ///
        /// @return The requested ScopedLinkedAccounts.NFT as a NonFungibleToken.NFT
        ///
        pub fun withdrawByAddress(address: Address): @NonFungibleToken.NFT {
            // Get the id of the assocated NFT
            let id: UInt64 = self.getIDOfNFTByAddress(address: address)
                ?? panic("This Collection does not contain an NFT associated with the given address ".concat(address.toString()))
            // Withdraw & return the NFT
            return <- self.withdraw(withdrawID: id)
        }

        /// Getter method to make indexing linked account Addresses to relevant NFT.ids easy
        ///
        /// @return This collection's addressToID mapping, identifying a linked account's associated NFT.id
        ///
        pub fun getAddressToID(): {Address: UInt64} {
            return self.addressToID
        }

        /// Returns an array of all linked account addresses
        ///
        /// @return an array containing the Addresses of the linked accounts
        ///
        pub fun getLinkedAccountAddresses(): [Address] {
            let addressToIDRef = &self.addressToID as &{Address: UInt64}
            return addressToIDRef.keys
        }

        /// Returns the id of the associated NFT wrapping the AuthAccount Capability for the given
        /// address
        ///
        /// @param ofAddress: Address associated with the desired ScopedLinkedAccounts.NFT
        ///
        /// @return The id of the associated ScopedLinkedAccounts.NFT or nil if it does not exist in this Collection
        ///
        pub fun getIDOfNFTByAddress(address: Address): UInt64? {
            let addressToIDRef = &self.addressToID as &{Address: UInt64}
            return addressToIDRef[address]
        }

        /// Returns a reference to the NFT as a Resolver based on the given address
        ///
        /// @param address: The address of the linked account
        ///
        /// @return A reference to the NFT as a Resolver
        ///
        pub fun borrowViewResolverFromAddress(address: Address): &{MetadataViews.Resolver} {
            return self.borrowViewResolver(
                id: self.addressToID[address] ?? panic("No ScopedLinkedAccounts.NFT with given Address")
            )
        }

        pub fun borrowAccessPointPublic(address: Address): &{AccessPointPublic}? {
            if let nftRef = self.borrowScopedLinkedAccountNFT(address: address) {
                return nftRef.borrowAccessPointPublic()
            }
            return nil
        }

        /// Allows the Collection to retrieve a reference to the NFT for a specified linked account address
        ///
        /// @param address: The Address of the linked account
        ///
        /// @return the reference to the linked account's AccessPoint
        ///
        pub fun borrowScopedLinkedAccountNFT(address: Address): &ScopedLinkedAccounts.NFT? {
            let addressToIDRef = &self.addressToID as &{Address: UInt64}
            if let id: UInt64 = addressToIDRef[address] {
                // Create an authorized reference to allow downcasting
                let ref = (&self.ownedNFTs[id] as auth &NonFungibleToken.NFT?)!
                return ref as! &ScopedLinkedAccounts.NFT
            }
            return nil
        }

        /// Returns a reference to the specified linked account's AccessPoint
        ///
        /// @param address: The address of the relevant linked account
        ///
        /// @return a reference to the linked account's AccessPoint or nil if the address is not of a linked account
        ///
        pub fun borrowAccessPoint(address: Address): &AccessPoint? {
            if let ref = self.borrowScopedLinkedAccountNFT(address: address) {
                return ref.borrowAccessPoint()
            }
            return nil
        }

        /// Add an existing account as a linked account to this Collection. This would be done in either a multisig
        /// transaction or by the linking account linking & publishing its AuthAccount Capability for the Collection's
        /// owner.
        ///
        /// @param accessPointCap: AccessPoint Capability for the account to be added as a linked account
        ///
        pub fun addAccessPoint(accessPointCap: Capability<&AccessPoint>) {
            pre {
                accessPointCap.check():
                    "Problem with given AccessPoint Capability!"
                !self.addressToID.containsKey(accessPointCap.borrow()!.getScopedAccountAddress()):
                    "Collection already has LinkedAccount.NFT for given account!"
                self.owner != nil:
                    "Cannot add a linked account without an owner for this Collection!"
            }

            /** --- Assign account variables --- */
            //
            // Get a &AuthAccount reference from the the given AuthAccount Capability
            let accessPointRef: &AccessPoint = accessPointCap.borrow()!
            // Assign parent & child address to identify sides of the link
            let childAddress: Address = accessPointRef.getScopedAccountAddress()
            // register this address as being permitted to be linked
            self.addPendingDeposit(address: childAddress)
            let parentAddress: Address = self.owner!.address

            /** --- Wrap caps in newly minted NFT & deposit --- */
            //
            // Create an NFT, increment supply, & deposit to this Collection before emitting MintedNFT
            let nft <-ScopedLinkedAccounts.mintNFT(accessPointCap: accessPointCap)
            let nftID: UInt64 = nft.id

            ScopedLinkedAccounts.totalSupply = ScopedLinkedAccounts.totalSupply + 1
            emit MintedNFT(nftID: nftID, accessPointID: accessPointRef.getID(), child: childAddress, parent: parentAddress, allowedTypes: accessPointRef.getAllowedCapabilityTypes())

            self.deposit(token: <-nft)
        }

        /// Remove NFT associated with given Address, effectively removing delegated access to the specified account
        /// by removal of the NFT from this Collection
        /// Note, removing a AccessPoint does not revoke key access linked account if it has been added. This should be
        /// done in the same transaction in which this method is called.
        ///
        /// @param withAddress: The Address of the linked account to remove from the mapping
        ///
        pub fun removeLinkedAccount(withAddress: Address) {
            pre {
                self.addressToID.containsKey(withAddress):
                    "This Collection does not have NFT with given Address: ".concat(withAddress.toString())
            }
            // Withdraw the NFT
            let nft: @ScopedLinkedAccounts.NFT <-self.withdrawByAddress(address: withAddress) as! @NFT
            let nftID: UInt64 = nft.id
            
            // Get a reference to the AccessPoint from the NFT
            let accessPointRef: &ScopedLinkedAccounts.AccessPoint = nft.getAccessPointRef()
            // Set the AccessPoint as inactive
            accessPointRef.setInactive()

            // Emit RemovedLinkedAccount & destroy NFT
            emit RemovedLinkedAccount(child: withAddress, parent: self.owner!.address)
            destroy nft
        }

        destroy () {
            pre {
                // Prevent destruction while account delegations remain in NFTs
                self.ownedNFTs.length == 0:
                    "Attempting to destroy Colleciton with remaining NFTs!"
            }
            destroy self.ownedNFTs
        }
        
    }

    /// Helper method to determine if a public key is active on an account by comparing the given key against all keys
    /// active on the given account.
    ///
    /// @param publicKey: A public key as a string
    /// @param address: The address of the account to query against
    ///
    /// @return True if the key is active on the account, false otherwise (including if the given public key string was
    /// invalid)
    ///
    pub fun isKeyActiveOnAccount(publicKey: String, address: Address): Bool {
        // Public key strings must have even length
        if publicKey.length % 2 == 0 {
            var keyIndex = 0
            var keysRemain = true
            // Iterate over keys on given account address
            while keysRemain {
                // Get the key as byte array
                if let keyArray = getAccount(address).keys.get(keyIndex: keyIndex)?.publicKey?.publicKey {
                    // Encode the key as a string and compare
                    if publicKey == String.encodeHex(keyArray) {
                        return !getAccount(address).keys.get(keyIndex: keyIndex)!.isRevoked
                    }
                    keyIndex = keyIndex + 1
                } else {
                    keysRemain = false
                }
            }
        }
        return false
    }

    /// Returns a new Collection
    ///
    pub fun createEmptyCollection(): @NonFungibleToken.Collection {
        emit CollectionCreated()
        return <-create Collection()
    }

    /// Returns a new AccessPointAdmin
    ///
    pub fun createAccessPointAdmin(): @AccessPointAdmin {
        return <-create AccessPointAdmin()
    }

    /// Function that returns all the Metadata Views implemented by a Non Fungible Token
    ///
    /// @return An array of Types defining the implemented views. This value will be used by
    ///         developers to know which parameter to pass to the resolveView() method.
    ///
    pub fun getViews(): [Type] {
        return [
            Type<MetadataViews.NFTCollectionData>(),
            Type<MetadataViews.NFTCollectionDisplay>()
        ]
    }

    /// Function that resolves a metadata view for this contract.
    ///
    /// @param view: The Type of the desired view.
    /// @return A structure representing the requested view.
    ///
    pub fun resolveView(_ view: Type): AnyStruct? {
        switch view {
            case Type<MetadataViews.NFTCollectionData>():
                return MetadataViews.NFTCollectionData(
                    storagePath: ScopedLinkedAccounts.CollectionStoragePath,
                    publicPath: ScopedLinkedAccounts.CollectionPublicPath,
                    providerPath: ScopedLinkedAccounts.CollectionPrivatePath,
                    publicCollection: Type<&ScopedLinkedAccounts.Collection{ScopedLinkedAccounts.CollectionPublic}>(),
                    publicLinkedType: Type<&ScopedLinkedAccounts.Collection{NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, ScopedLinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}>(),
                    providerLinkedType: Type<&ScopedLinkedAccounts.Collection{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic, ScopedLinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}>(),
                    createEmptyCollectionFunction: (fun (): @NonFungibleToken.Collection {
                        return <-ScopedLinkedAccounts.createEmptyCollection()
                    })
                )
            case Type<MetadataViews.NFTCollectionDisplay>():
                let media = MetadataViews.Media(
                    file: MetadataViews.HTTPFile(
                        url: "https://assets.website-files.com/5f6294c0c7a8cdd643b1c820/5f6294c0c7a8cda55cb1c936_Flow_Wordmark.svg"
                    ),
                    mediaType: "image/svg+xml"
                )
        }
        return nil
    }

    /// Contract mint method enabling caller to mint an NFT, wrapping the provided Capabilities
    ///
    /// @param accessPointCap: The AccessPoint Capability that will be wrapped in the minted NFT
    ///
    /// @return the newly created NFT
    ///
    access(contract) fun mintNFT(accessPointCap: Capability<&AccessPoint>): @NFT {
        return <-create NFT(accessPointCapability: accessPointCap)
    }

    init() {

        self.totalSupply = 0

        // Assign Collection paths
        self.CollectionStoragePath = /storage/LinkedAccountCollection
        self.CollectionPublicPath = /public/LinkedAccountCollection
        self.CollectionPrivatePath = /private/LinkedAccountCollection
        // Assign AccessPoint paths
        self.AccessPointAdminStoragePath = /storage/ScopedAccountsAccessPointAdmin
        self.AccessPointAdminPrivatePath = /private/ScopedAccountsAccessPointAdmin
        self.AccessPointStoragePath = /storage/ScopedAccountsAccessPoint
        self.AccessPointPublicPath = /public/ScopedAccountsAccessPoint
        self.AccessPointPrivatePath = /private/ScopedAccountsAccessPoint
        self.AccessorStoragePath = /storage/ScopedAccountsAccessor

        emit ContractInitialized()
    }
}
 