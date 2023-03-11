import NonFungibleToken from "./utility/NonFungibleToken.cdc"
import ViewResolver from "./utility/ViewResolver.cdc"
import FungibleToken from "./utility/FungibleToken.cdc"
import FlowToken from "./utility/FlowToken.cdc"
import MetadataViews from "./utility/MetadataViews.cdc"
import LinkedAccountMetadataViews from "./LinkedAccountMetadataViews.cdc"

/// This contract is an attempt at establishing and representing a
/// parent-child hierarchy between linked accounts.
///
/// The AccountAdministrator allows a parent account to add child accounts, and
/// maintains delegated access in a stored mapping. An account is deemed a child of a
/// parent if the parent maintains delegated access on the child account by way of AuthAccount
/// Capability wrapped in a Owner and saved in a AccountAdministrator. By
/// the constructs defined in this contract, a linked account can be identified by a stored
/// AccountHandler.
///
/// While one generally would not want to share account access with other parties,
/// this can be helpful in a low-stakes environment where the parent account's owner
/// wants to delegate transaction signing to a secondary party. The idea for this setup
/// was born out of pursuit of a more seamless on-chain gameplay UX where a user could
/// let a game client submit transactions on their behalf without signing over the whole
/// of their primary account, and do so in a way that didn't require custom a Capability.
///
/// With that said, users should bear in mind that any assets in a linked account incur
/// obvious custodial risk, and that it's generally an anti-pattern to pass around AuthAccounts.
/// In this case, a user owns both accounts so they are technically passing an AuthAccount
/// to themselves in calls to resources that reside in their own account, so it was deemed
/// a valid application of the pattern. That said, a user should be cognizant of the party
/// with key access on the linked account as this pattern requires some degree of trust in the
/// custodying party.
///
pub contract LinkedAccounts : NonFungibleToken, ViewResolver {

    /// The number of Owner tokens in existence
    pub var totalSupply: UInt64

    pub event AddedLinkedAccount(parent: Address, child: Address)
    pub event LinkedAccountGrantedCapability(parent: Address, child: Address, capabilityType: Type)
    pub event CapabilityRevokedFromLinkedAccount(parent: Address, child: Address, capabilityType: Type)
    pub event RemovedLinkedAccount(parent: Address, child: Address)
    pub event AccountAdministratorCreated()

    // NFT conforming events
    pub event ContractInitialized()
    pub event Withdraw(id: UInt64, from: Address?)
    pub event Deposit(id: UInt64, to: Address?)

    /* Standard paths */
    //
    pub let AccountAdministratorStoragePath: StoragePath
    pub let AccountAdministratorPublicPath: PublicPath
    pub let AccountAdministratorPrivatePath: PrivatePath
    pub let AccountHandlerStoragePath: StoragePath
    pub let AccountHandlerPublicPath: PublicPath
    pub let AccountHandlerPrivatePath: PrivatePath

    /** --- AccountHandler --- */
    //
    pub resource interface AccountHandlerPublic {
        pub fun getParentAddress(): Address
        pub fun getGrantedCapabilityTypes(): [Type]
        pub fun isCurrentlyActive(): Bool
    }

    /// Identifies an account as a child account and maintains info
    /// about its parent & association as well as Capabilities granted by
    /// its parent's AccountAdministrator
    ///
    pub resource AccountHandler : AccountHandlerPublic, MetadataViews.Resolver {
        /// Pointer to this account's parent account
        access(contract) let parentAddress: Address
        /// The address of the account where the ccountHandler resource resides
        access(contract) let address: Address
        /// Metadata about the purpose of this child account guarantees standard minimum metadata is stored
        /// about linked accounts
        access(contract) let metadata: AnyStruct{LinkedAccountMetadataViews.AccountMetadata}
        /// Resolver struct to increase the flexibility, allowing implementers to resolve their own structs
        access(contract) let resolver: AnyStruct{LinkedAccountMetadataViews.MetadataResolver}?
        /// Capabilities that have been granted by the parent account
        access(contract) let grantedCapabilities: {Type: Capability}
        /// Flag denoting whether link to parent is still active
        access(contract) var isActive: Bool

        init(
            parentAddress: Address,
            address: Address,
            metadata: AnyStruct{LinkedAccountMetadataViews.AccountMetadata},
            resolver: AnyStruct{LinkedAccountMetadataViews.MetadataResolver}?
        ) {
            self.parentAddress = parentAddress
            self.address = address
            self.metadata = metadata
            self.grantedCapabilities = {}
            self.resolver = resolver
            self.isActive = true
        }

        /** --- MetadataViews.Resolver --- */
        //
        /// Returns the metadata view types supported by this Handler
        ///
        /// @return an array of metadata view types
        ///
        pub fun getViews(): [Type] {
            let views: [Type] = []
            if self.resolver != nil {
                views.appendAll(self.resolver!.getViews())
            }
            views.appendAll([
                Type<LinkedAccountMetadataViews.AccountInfo>(),
                self.metadata.getType()
            ])
            return views
        }
        
        /// Returns the requested view if supported or nil otherwise
        ///
        /// @param view: The Type of metadata struct requests
        ///
        /// @return the metadata struct if supported or nil
        ///
        pub fun resolveView(_ view: Type): AnyStruct? {
            switch view {
                case Type<LinkedAccountMetadataViews.AccountInfo>():
                    return LinkedAccountMetadataViews.AccountInfo(
                        name: self.metadata.name,
                        description: self.metadata.description,
                        icon: self.metadata.icon,
                        externalURL: self.metadata.externalURL
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

        /** --- AccountHandlerPublic --- */
        //
        /// Returns the Address of this linked account's parent AccountAdministrator
        ///
        pub fun getParentAddress(): Address {
            return self.parentAddress
        }
        
        /// Returns the metadata related to this account's association
        ///
        pub fun getAccountMetadata(): AnyStruct{LinkedAccountMetadataViews.AccountMetadata} {
            return self.metadata
        }

        /// Returns the types of Capabilities this Handler has been granted
        ///
        /// @return An array of the Types of Capabilities this resource has access to
        ///         in its grantedCapabilities mapping
        ///
        pub fun getGrantedCapabilityTypes(): [Type] {
            return self.grantedCapabilities.keys
        }
        
        /// Returns whether the link between this Handler and its associated AccountAdministrator
        /// is still active - in practice whether the linked AccountAdministrator has removed
        /// this Handler's Capability
        ///
        pub fun isCurrentlyActive(): Bool {
            return self.isActive
        }

        /** --- AccountHandler --- */
        //
        /// Retrieves a granted Capability as a reference or nil if it does not exist. 
        /// 
        //  **NB**: This is a temporary solution for Capability auditing & easy revocation 
        /// until CapabilityControllers make their way to Cadence, enabling a parent account 
        /// to issue, audit and easily revoke Capabilities to child accounts.
        /// 
        /// @param type: The Type of Capability being requested
        ///
        /// @return A reference to the Capability or nil if a Capability of given Type is not
        ///         available
        ///
        pub fun getGrantedCapabilityAsRef(_ type: Type): &Capability? {
            pre {
                self.isActive: "AccountHandler has been de-permissioned by parent!"
            }
            return &self.grantedCapabilities[type] as &Capability?
        }

        /// Inserts the given Capability into this Handler's grantedCapabilities mapping
        ///
        /// @param cap: The Capability being granted
        ///
        access(contract) fun grantCapability(_ cap: Capability) {
            pre {
                !self.grantedCapabilities.containsKey(cap.getType()):
                    "Already granted Capability of given type!"
            }
            self.grantedCapabilities.insert(key: cap.getType(), cap)
        }

        /// Removes the Capability of given Type from this Handler's grantedCapabilities
        /// mapping
        ///
        /// @param type: The Type of Capability to be removed
        ///
        /// @return the removed Capability or nil if it did not exist
        ///
        access(contract) fun revokeCapability(_ type: Type): Capability? {
            return self.grantedCapabilities.remove(key: type)
        }

        /// Sets the isActive Bool flag to false
        ///
        access(contract) fun setInactive() {
            self.isActive = false
        }
    }

    /** --- Owner --- */
    //
    /// Publicly accessible Capability for linked account wrapping resource
    ///
    pub resource interface OwnerPublic {
        pub let id: UInt64
        pub fun getChildAccountAddress(): Address
        pub fun getParentAccountAddress(): Address
        pub fun getHandlerPublicRef(): &AccountHandler{AccountHandlerPublic}
    }

    // TODO: Handle renaming
    /// Wrapper for the linked account's metadata, AuthAccount, and AccountHandler Capabilities
    /// implemented as an NFT
    ///
    pub resource NFT: NonFungibleToken.INFT, OwnerPublic, MetadataViews.Resolver {
        pub let id: UInt64
        /// The AuthAccount Capability for the linked account this Owner represents
        access(self) let authAccountCapability: Capability<&AuthAccount>
        /// Capability for the relevant AccountHandler
        access(self) var handlerCapability: Capability<&AccountHandler>

        init(
            authAccountCap: Capability<&AuthAccount>,
            handlerCap: Capability<&AccountHandler>
        ) {
            self.id = self.uuid
            self.authAccountCapability = authAccountCap
            self.handlerCapability = handlerCap
        }

        /// Function that returns all the Metadata Views implemented by an Owner
        ///
        /// @return An array of Types defining the implemented views. This value will be used by
        ///         developers to know which parameter to pass to the resolveView() method.
        ///
        pub fun getViews(): [Type] {
            let handlerRef: &LinkedAccounts.AccountHandler = self.handlerCapability.borrow()
                ?? panic("Problem with AccountHandler Capability in this Owner")
            let views = handlerRef.getViews()
            views.appendAll([
                Type<MetadataViews.NFTCollectionData>(),
                Type<MetadataViews.NFTCollectionDisplay>()
            ])
            return views
        }

        /// Function that resolves a metadata view for this ChildAccount.
        ///
        /// @param view: The Type of the desired view.
        /// @return A structure representing the requested view.
        ///
        pub fun resolveView(_ view: Type): AnyStruct? {
            if view == Type<MetadataViews.NFTCollectionData>() ||
                view == Type<MetadataViews.NFTCollectionDisplay>() {
                return LinkedAccounts.resolveView(view)
            } else {
                let handlerRef: &LinkedAccounts.AccountHandler = self.handlerCapability.borrow()
                ?? panic("Problem with AccountHandler Capability in this Owner")
                return handlerRef.resolveView(view)
            }
            
        }

        /// Get a reference to the child AuthAccount object.
        ///
        pub fun getAuthAcctRef(): &AuthAccount {
            return self.authAccountCapability.borrow() ?? panic("Problem with AuthAccount Capability in Owner!")
        }

        /// Returns a reference to the AccountHandler
        ///
        pub fun getAccountHandlerRef(): &AccountHandler {
            return self.handlerCapability.borrow() ?? panic("Problem with AccountHandler Capability in Owner!")
        }

        /** --- OwnerPublic --- */
        //
        /// Returns the child account address this Owner manages a Capability for
        ///
        /// @return the address of the account this Owner has delegated access to
        ///
        pub fun getChildAccountAddress(): Address {
            return self.getAuthAcctRef().address
        }

        /// Returns the address on the parent side of the account link
        ///
        /// @return the address of the account that has been given delegated access
        ///
        pub fun getParentAccountAddress(): Address {
            return self.getHandlerPublicRef().getParentAddress()
        }

        /// Returns a reference to the AccountHandler as AccountHandlerPublic
        ///
        /// @return a reference to the AccountHandler as AccountHandlerPublic 
        ///
        pub fun getHandlerPublicRef(): &AccountHandler{AccountHandlerPublic} {
            return self.handlerCapability.borrow() ?? panic("Problem with AccountHandler Capability in Owner!")
        }
    }

    /** --- AccountAdministrator --- */
    //
    /// Interface that allows one to view information about the owning account's
    /// child accounts including the addresses for all child accounts and information
    /// about specific child accounts by Address
    ///
    pub resource interface AccountAdministratorPublic {
        pub fun getLinkedAccountAddresses(): [Address]
        pub fun getOwnerIDFromAddress(address: Address): UInt64?
        pub fun deposit(token: @NonFungibleToken.NFT)
        pub fun getIDs(): [UInt64]
        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT
        pub fun borrowOwnerPublic(id: UInt64): &LinkedAccounts.NFT{LinkedAccounts.OwnerPublic}? {
            post {
                (result == nil) || (result?.id == id):
                    "Cannot borrow ExampleNFT reference: the ID of the returned reference is incorrect"
            }
        }
    }

    /// Resource allows for management of on-chain associations between accounts.
    /// Note that while creating child accounts is available in this resource,
    /// revoking keys on those child accounts is not.
    /// 
    pub resource AccountAdministrator : AccountAdministratorPublic, NonFungibleToken.Provider, NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, MetadataViews.ResolverCollection {

        // pub let linkedAccounts: @{Address: Owner}
        // pub let idToAddress: {UInt64: Address}
        pub var ownedNFTs: @{UInt64: NonFungibleToken.NFT}
        pub let addressToID: {Address: UInt64}

        init() {
            // self.linkedAccounts <- {}
            // self.idToAddress = {}
            self.ownedNFTs <-{}
            self.addressToID = {}
        }
        
        /** --- MetadataViews.ResolverCollection --- */
        //
        /// Returns the Owner as a Resolver for the specified ID
        ///
        /// @param id: The id of the Owner
        ///
        /// @return A reference to the Owner as a Resolver
        ///
        pub fun borrowViewResolver(id: UInt64): &{MetadataViews.Resolver} {
            let nft = &self.ownedNFTs[id] as auth &NonFungibleToken.NFT?
                ?? panic("Administrator does not have Owner with specified ID")
            let owner = nft as! &LinkedAccounts.NFT
            return owner as &AnyResource{MetadataViews.Resolver}
        }

        /// Returns the IDs of the contained Owner
        ///
        /// @return an array of the contained Owner resources
        ///
        pub fun getIDs(): [UInt64] {
            return self.addressToID.values
        }

        // TODO: Comment
        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT {
            return &self.ownedNFTs[id] as &NonFungibleToken.NFT? ?? panic("Administrator does not have Owner with specified ID")
        }

        // TODO: Comment
        pub fun borrowNFTSafe(id: UInt64): &NonFungibleToken.NFT? {
            return &self.ownedNFTs[id] as &NonFungibleToken.NFT?
        }
        
        // TODO: Comment
        pub fun borrowOwnerPublic(id: UInt64): &LinkedAccounts.NFT{LinkedAccounts.OwnerPublic}? {
            if let nft = &self.ownedNFTs[id] as auth &NonFungibleToken.NFT? {
                let owner = nft as! &LinkedAccounts.NFT
                return owner as &LinkedAccounts.NFT{LinkedAccounts.OwnerPublic}?
            }
            return nil
        }

        // TODO: Comment
        pub fun deposit(token: @NonFungibleToken.NFT) {
            let token <- token as! @LinkedAccounts.NFT
            let id: UInt64 = token.id

            // add the new token to the dictionary which removes the old one
            let oldToken <- self.ownedNFTs[id] <- token

            // TODO: Decide on behavior for the event
            assert(self.owner != nil, message: "Cannot transfer LinkedAccount.Owner to unknown party!")
            emit Deposit(id: id, to: self.owner?.address)

            destroy oldToken
        }
        
        // TODO: Comment & Implementation
        // pub fun withdraw(withdrawID: UInt64): @NonFungibleToken.NFT

        /** --- AccountAdministratorPublic --- */
        //
        /// Returns an array of all child account addresses
        ///
        /// @return an array containing the Addresses of the linked accounts
        pub fun getLinkedAccountAddresses(): [Address] {
            return self.addressToID.keys
        }

        /// Given an address, returns the id of the associated Owner associated with
        /// the linked account
        ///
        /// @param address: The Address of the account in question
        ///
        /// @return the Owner.id of the associated resource
        ///
        pub fun getOwnerIDFromAddress(address: Address): UInt64? {
            return self.addressToID[address]
        }

        /** --- AccountAdministrator --- */
        //
        /// Returns a reference to the Owner as a Resolver based on the given address
        ///
        /// @param address: The address of the linked account
        ///
        /// @return A reference to the Owner as a Resolver
        ///
        pub fun borrowViewResolverFromAddress(address: Address): &{MetadataViews.Resolver} {
            return self.borrowViewResolver(
                id: self.addressToID[address] ?? panic("No LinkedAccounts.Owner with given Address")
            )
        }

        /// Allows the AccountAdministrator to retrieve a reference to the Owner
        /// for a specified child account address
        ///
        /// @param address: The Address of the child account
        ///
        /// @return the reference to the child account's ChildAccountTag
        ///
        pub fun borrowLinkedAccountNFT(address: Address): &NFT? {
            return &self.ownedNFTs[address] as &NFT?
        }

        /// Returns a reference to the specified linked account's AuthAccount
        ///
        /// @param address: The address of the relevant linked account
        ///
        /// @return the linked account's AuthAccount as ephemeral reference or nil if the
        ///         address is not of a linked account
        ///
        pub fun getChildAccountRef(address: Address): &AuthAccount? {
            if let ownerRef = self.borrowOwner(address: address) {
                return ownerRef.getAuthAcctRef()
            }
            return nil
        }

        /// Returns a reference to the specified linked account's AccountHandler
        ///
        /// @param address: The address of the relevant linked account
        ///
        /// @return the child account's AccountHandler as ephemeral reference or nil if the
        ///         address is not of a linked account
        ///
        pub fun getAccountHandlerRef(address: Address): &AccountHandler? {
            if let ownerRef = self.borrowOwner(address: address) {
                return ownerRef.getAccountHandlerRef()
            }
            return nil
        }

        /// Add an existing account as a child account to this Administrator resource. This would be done in
        /// a multisig transaction which should be possible if the parent account controls both
        ///
        /// @param childAccountCap: AuthAccount Capability for the account to be added as a child account
        /// @param childAccountInfo: Metadata struct containing relevant data about the account being linked
        ///
        pub fun addAsChildAccount(
            linkedAccountCap: Capability<&AuthAccount>,
            linkedAccountMetadata: AnyStruct{LinkedAccountMetadataViews.AccountMetadata},
            linkedAccountMetadataResolver: AnyStruct{LinkedAccountMetadataViews.MetadataResolver}?,
            handlerPathSuffix: String
        ) {
            pre {
                linkedAccountCap.check():
                    "Problem with given AuthAccount Capability!"
                !self.linkedAccounts.containsKey(linkedAccountCap.borrow()!.address):
                    "Child account with given address already exists!"
                self.owner != nil:
                    "Cannot add a linked account without an owner for this administrator!"
            }
            // Get a &AuthAccount reference from the the given AuthAccount Capability
            let linkedAccountRef: &AuthAccount = linkedAccountCap.borrow()!
            // Assign parent & child address to identify sides of the link
            let childAddress = linkedAccountRef.address
            let parentAddress = self.owner!.address

            // Construct paths for the AccountHandler & its Capabilities
            let handlerStoragePath = StoragePath(identifier: handlerPathSuffix)
                ?? panic("Could not construct StoragePath for AccountHandler with given suffix")
            let handlerPublicPath = PublicPath(identifier: handlerPathSuffix)
                ?? panic("Could not construct PublicPath for AccountHandler with given suffix")
            let handlerPrivatePath = PrivatePath(identifier: handlerPathSuffix)
                ?? panic("Could not construct PrivatePath for AccountHandler with given suffix")

            // Create a AccountHandler
            let handler <-create AccountHandler(
                    parentAddress: parentAddress,
                    address: childAddress,
                    metadata: linkedAccountMetadata,
                    resolver: linkedAccountMetadataResolver
                )
            // Save the AccountHandler in the child account's storage & link
            linkedAccountRef.save(<-handler, to: handlerStoragePath)
            // Ensure public Capability linked
            linkedAccountRef.link<&AccountHandler{AccountHandlerPublic}>(
                handlerPublicPath,
                target: handlerStoragePath
            )
            // Ensure private Capability linked
            linkedAccountRef.link<&AccountHandler>(
                handlerPrivatePath,
                target: handlerStoragePath
            )
            // Get a Capability to the linked AccountHandler Cap in linked account's private storage
            let handlerCap = linkedAccountRef
                .getCapability<&
                    AccountHandler
                >(
                    handlerPrivatePath
                )
            // Ensure the capability is valid before inserting it in administrator's linkedAccounts mapping
            assert(handlerCap.check(), message: "Problem linking AccountHandler Capability in new child account!")

            // Create a Owner, increment supply, & insert to linkedAccounts mapping
            let owner <-create Owner(
                    authAccountCap: linkedAccountCap,
                    handlerCap: handlerCap
                )
            LinkedAccounts.totalSupply = LinkedAccounts.totalSupply + 1
            
            // Add the id & owner to the relevant mappings
            self.idToAddress[owner.id] = childAddress
            self.linkedAccounts[childAddress] <-! owner

            emit AddedLinkedAccount(parent: parentAddress, child: childAddress)
        }

        /// Adds the given Capability to the AccountHandler at the provided Address
        ///
        /// @param to: Address which is the key for the AccountHandler Cap
        /// @param cap: Capability to be added to the AccountHandler
        ///
        pub fun addCapability(to: Address, _ cap: Capability) {
            pre {
                self.linkedAccounts.containsKey(to):
                    "No linked account with given Address!"
            }
            // Get ref to handler
            let handlerRef = self.getAccountHandlerRef(
                    address: to
                ) ?? panic("Problem with AccountHandler Capability for given address: ".concat(to.toString()))
            let capType: Type = cap.getType()
            
            // Pass the Capability to the linked account via the handler & emit
            handlerRef.grantCapability(cap)
            emit LinkedAccountGrantedCapability(parent: self.owner!.address, child: to, capabilityType: capType)
        }

        /// Removes the capability of the given type from the AccountHandler with the given Address
        ///
        /// @param from: Address indexing the AccountHandler Capability
        /// @param type: The Type of Capability to be removed from the AccountHandler
        ///
        pub fun removeCapability(from: Address, type: Type) {
            pre {
                self.linkedAccounts.containsKey(from):
                    "No linked account with given Address!"
            }
            // Get ref to handler and remove
            let handlerRef = self.getAccountHandlerRef(
                    address: from
                ) ?? panic("Problem with AccountHandler Capability for given address: ".concat(from.toString()))
            // Revoke Capability & emit
            handlerRef.revokeCapability(type)
                ?? panic("Capability not properly revoked")
            emit CapabilityRevokedFromLinkedAccount(parent: self.owner!.address, child: from, capabilityType: type)
        }

        /// Remove AccountHandler, returning its Capability if it exists. Note, doing so
        /// does not revoke key access linked account if it has been added. This should 
        /// be done in the same transaction in which this method is called.
        ///
        /// @param withAddress: The Address of the linked account to remove from the mapping
        ///
        /// @return the Address of the account removed or nil if it wasn't linked to begin with
        ///
        pub fun removeLinkedAccount(withAddress: Address): Address? {
            if let owner: @Owner <-self.linkedAccounts.remove(key: withAddress) {
                let ownerID = owner.id
                // Get a reference to the AccountHandler from the Capability
                let handlerRef = owner.getAccountHandlerRef()
                // Set the handler as inactive
                handlerRef.setInactive()

                // Remove all capabilities from the AccountHandler
                for capType in handlerRef.getGrantedCapabilityTypes() {
                    handlerRef.revokeCapability(capType)
                }

                // Destroy the owner, emit, & return the removed entry in idToAddress
                destroy owner
                emit RemovedLinkedAccount(parent: self.owner!.address, child: withAddress)
                return self.idToAddress.remove(key: ownerID)
            }
            return nil
        }

        destroy () {
            pre {
                self.ownedNFTs.length == 0:
                    "Attempting to destroy AccountAdministrator with remaining Owners!"
            }
            destroy self.ownedNFTs
        }
        
    }

    /// Returns true if the provided public key (provided as String) has not been
    /// revoked on the given account address
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

    /// Returns a new AccountAdministrator
    ///
    pub fun createAccountAdministrator(): @AccountAdministrator {
        emit AccountAdministratorCreated()
        return <-create AccountAdministrator()
    }

    pub fun createEmptyCollection(): @NonFungibleToken.Collection {
        emit AccountAdministratorCreated()
        return <-create AccountAdministrator()
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
                    storagePath: LinkedAccounts.AccountAdministratorStoragePath,
                    publicPath: LinkedAccounts.AccountAdministratorPublicPath,
                    providerPath: LinkedAccounts.AccountAdministratorPrivatePath,
                    publicCollection: Type<&LinkedAccounts.AccountAdministrator{LinkedAccounts.AccountAdministratorPublic}>(),
                    publicLinkedType: Type<&LinkedAccounts.AccountAdministrator{LinkedAccounts.AccountAdministratorPublic,NonFungibleToken.CollectionPublic,NonFungibleToken.Receiver,MetadataViews.ResolverCollection}>(),
                    providerLinkedType: Type<&LinkedAccounts.AccountAdministrator{LinkedAccounts.AccountAdministratorPublic,NonFungibleToken.CollectionPublic,NonFungibleToken.Provider,MetadataViews.ResolverCollection}>(),
                    createEmptyCollectionFunction: (fun (): @NonFungibleToken.Collection {
                        return <-LinkedAccounts.createEmptyCollection()
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

    init() {

        self.totalSupply = 0

        // Assign AccountAdministrator paths
        self.AccountAdministratorStoragePath = /storage/LinkedAccountAdministrator
        self.AccountAdministratorPublicPath = /public/LinkedAccountAdministrator
        self.AccountAdministratorPrivatePath = /private/LinkedAccountAdministrator
        // Assign AccountHandler paths
        self.AccountHandlerStoragePath = /storage/LinkedAccountHandler
        self.AccountHandlerPublicPath = /public/LinkedAccountHandler
        self.AccountHandlerPrivatePath = /private/LinkedAccountHandler

        emit ContractInitialized()
    }
}
 