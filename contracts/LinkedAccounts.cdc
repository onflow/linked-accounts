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
/// Handler.
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

    // NFT conforming events
    pub event ContractInitialized()
    pub event Withdraw(id: UInt64, from: Address?)
    pub event Deposit(id: UInt64, to: Address?)
    
    // LinkedAccounts Events
    pub event AddedLinkedAccount(parent: Address, child: Address)
    pub event LinkedAccountGrantedCapability(parent: Address, child: Address, capabilityType: Type)
    pub event CapabilityRevokedFromLinkedAccount(parent: Address, child: Address, capabilityType: Type)
    pub event RemovedLinkedAccount(parent: Address, child: Address)
    pub event CollectionCreated()

    // Canonical paths
    pub let CollectionStoragePath: StoragePath
    pub let CollectionPublicPath: PublicPath
    pub let CollectionPrivatePath: PrivatePath
    pub let HandlerStoragePath: StoragePath
    pub let HandlerPublicPath: PublicPath
    pub let HandlerPrivatePath: PrivatePath

    /** --- Handler --- */
    //
    pub resource interface HandlerPublic {
        pub fun getParentAddress(): Address
        pub fun getGrantedCapabilityTypes(): [Type]
        pub fun isCurrentlyActive(): Bool
    }

    /// Identifies an account as a child account and maintains info about its parent & association as well as
    /// Capabilities granted by its parent account's Collection
    ///
    pub resource Handler : HandlerPublic, MetadataViews.Resolver {
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
        /// @return An array of metadata view types
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
        /// @return The metadata of requested Type if supported and nil otherwise
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

        /** --- HandlerPublic --- */
        //
        /// Returns the Address of this linked account's parent Collection
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
        /// @return An array of the Types of Capabilities this resource has access to in its grantedCapabilities
        ///         mapping
        ///
        pub fun getGrantedCapabilityTypes(): [Type] {
            return self.grantedCapabilities.keys
        }
        
        /// Returns whether the link between this Handler and its associated Collection is still active - in
        /// practice whether the linked Collection has removed this Handler's Capability
        ///
        pub fun isCurrentlyActive(): Bool {
            return self.isActive
        }

        /** --- Handler --- */
        //
        /// Retrieves a granted Capability as a reference or nil if it does not exist. until CapabilityControllers make
        /// 
        //  **NB**: This is a temporary solution for Capability auditing & easy revocation 
        /// their way to Cadence, enabling a parent account to issue, audit and easily revoke Capabilities to linked
        /// accounts.
        /// 
        /// @param type: The Type of Capability being requested
        ///
        /// @return A reference to the Capability or nil if a Capability of given Type is not
        ///         available
        ///
        pub fun getGrantedCapabilityAsRef(_ type: Type): &Capability? {
            pre {
                self.isActive: "LinkedAccounts.Handler has been de-permissioned by parent!"
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

    /** --- NFT --- */
    //
    /// Publicly accessible Capability for linked account wrapping resource, protecting the wrapped Capabilities
    /// from public access via reference as implemented in LinkedAccount.NFT
    ///
    pub resource interface NFTPublic {
        pub let id: UInt64
        pub fun getChildAccountAddress(): Address
        pub fun getParentAccountAddress(): Address
        pub fun getHandlerPublicRef(): &Handler{HandlerPublic}
    }

    /// Wrapper for the linked account's metadata, AuthAccount, and Handler Capabilities
    /// implemented as an NFT
    ///
    pub resource NFT : NFTPublic, NonFungibleToken.INFT, MetadataViews.Resolver {
        pub let id: UInt64
        /// The AuthAccount Capability for the linked account this Owner represents
        access(self) let authAccountCapability: Capability<&AuthAccount>
        /// Capability for the relevant AccountHandler
        access(self) var handlerCapability: Capability<&Handler>

        init(
            authAccountCap: Capability<&AuthAccount>,
            handlerCap: Capability<&Handler>
        ) {
            self.id = self.uuid
            self.authAccountCapability = authAccountCap
            self.handlerCapability = handlerCap
        }

        /// Function that returns all the Metadata Views implemented by an NFT & by extension the relevant Handler
        ///
        /// @return An array of Types defining the implemented views. This value will be used by developers to know
        ///         which parameter to pass to the resolveView() method.
        ///
        pub fun getViews(): [Type] {
            let handlerRef: &LinkedAccounts.Handler = self.handlerCapability.borrow()
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
        ///
        /// @return A struct representing the requested view.
        ///
        pub fun resolveView(_ view: Type): AnyStruct? {
            if view == Type<MetadataViews.NFTCollectionData>() ||
                view == Type<MetadataViews.NFTCollectionDisplay>() {
                return LinkedAccounts.resolveView(view)
            } else {
                let handlerRef: &LinkedAccounts.Handler = self.handlerCapability.borrow()
                ?? panic("Problem with AccountHandler Capability in this Owner")
                return handlerRef.resolveView(view)
            }
            
        }

        /// Get a reference to the child AuthAccount object.
        ///
        pub fun getAuthAcctRef(): &AuthAccount {
            return self.authAccountCapability.borrow() ?? panic("Problem with AuthAccount Capability in Owner!")
        }

        /// Returns a reference to the Handler
        ///
        pub fun getHandlerRef(): &Handler {
            return self.handlerCapability.borrow() ?? panic("Problem with LinkedAccounts.Handler Capability in Owner!")
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

    /** --- Collection --- */
    //
    /// Interface that allows one to view information about the owning account's
    /// child accounts including the addresses for all child accounts and information
    /// about specific child accounts by Address
    ///
    pub resource interface CollectionPublic {
        pub fun getLinkedAccountAddresses(): [Address]
        pub fun getIDOfLinkedAccountNFT(ofAddress: Address): UInt64?
        pub fun deposit(token: @NonFungibleToken.NFT)
        pub fun getIDs(): [UInt64]
        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT
        pub fun borrowLinkedAccountsNFTPublic(id: UInt64): &LinkedAccounts.NFT{LinkedAccounts.NFTPublic}? {
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
    pub resource Collection : CollectionPublic, NonFungibleToken.Provider, NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, MetadataViews.ResolverCollection {

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

        /// Returns the IDs of the NFTs in this Collection
        ///
        /// @return an array of the contained Owner resources
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
            return &self.ownedNFTs[id] as &NonFungibleToken.NFT? ?? panic("Administrator does not have Owner with specified ID")
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
        
        /// Returns a reference to the specified LinkedAccounts.NFT as NFTPublic with given ID or nil
        ///
        /// @param id: The id of the requested LinkedAccounts.NFT as NFTPublic
        ///
        /// @return The requested LinkedAccounts.NFTublic or nil if there is not an NFT with requested id in this
        ///         Collection
        ///
        pub fun borrowLinkedAccountsNFTPublic(id: UInt64): &LinkedAccounts.NFT{LinkedAccounts.NFTPublic}? {
            if let nft = &self.ownedNFTs[id] as auth &NonFungibleToken.NFT? {
                let owner = nft as! &LinkedAccounts.NFT
                return owner as &LinkedAccounts.NFT{LinkedAccounts.NFTPublic}?
            }
            return nil
        }

        // TODO: Consider - Do we want anyone to be able to deposit one of these NFTs into another's collection
        /// Takes a given NonFungibleToken.NFT and adds it to this Collection's mapping of ownedNFTs, emitting both
        /// Deposit and AddedLinkedAccount since depositing LinkedAccounts.NFT is effectively giving a Collection owner
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
            // Assign scoped variables from LinkedAccounts.NFT
            let token <- token as! @LinkedAccounts.NFT
            let linkedAccountAddress: Address = token.getAuthAcctRef().address
            let id: UInt64 = token.id
            
            // Ensure associated Handler address matches the linked account address
            assert(
                token.getHandlerRef().address == linkedAccountAddress,
                message: "LinkedAccount.NFT assocaited Handler address & AuthAccount addresses do not match!"
            )
            // Ensure this Collection has not already been granted delegated access to the given account
            assert(
                !self.addressToID.containsKey(linkedAccountAddress),
                message: "Already have delegated access to account address: ".concat(linkedAccountAddress.toString())
            )

            // Add the new token to the dictionary which removes the old one
            let oldToken <- self.ownedNFTs[id] <- token

            // Emit events
            emit Deposit(id: id, to: self.owner?.address)
            emit AddedLinkedAccount(parent: self.owner!.address, child: linkedAccountAddress)

            destroy oldToken
        }
        
        /// Withdraws the LinkedAccounts.NFT with the given id as a NonFungibleToken.NFT, emitting standard Withdraw
        /// event along with RemovedLinkedAccount event, denoting the delegated access for the account associated with
        /// the NFT has been removed from this Collection
        ///
        /// @param withdrawID: The id of the requested NFT
        ///
        /// @return The requested LinkedAccounts.NFT as a NonFungibleToken.NFT
        ///
        pub fun withdraw(withdrawID: UInt64): @NonFungibleToken.NFT {
            pre {
                self.ownedNFTs.containsKey(withdrawID):
                    "Collection does not contain NFT with given id: ".concat(withdrawID.toString())
                self.owner!.address != nil:
                    "Cannot withdraw LinkedAccount.NFT from unknown party!"
            }
            // Get the token from the ownedNFTs mapping
            let token: @NonFungibleToken.NFT <- self.ownedNFTs.remove(key: withdrawID)!
            
            // Loading a dictionary can be heavy - get a reference instead
            let addressToIDRef = &self.addressToID as &{Address: UInt64}
            // Get the Address associated with the withdrawing token id
            let childAddress: Address = addressToIDRef.keys[
                    addressToIDRef.values.firstIndex(of: withdrawID)!
                ]!
            // Remove the address entry in our secondary mapping
            self.addressToID.remove(key: childAddress)!

            // Emit events & return
            emit Withdraw(id: token.id, from: self.owner?.address)
            emit RemovedLinkedAccount(parent: self.owner!.address, child: childAddress)
            return <-token
        }

        /// Withdraws the LinkedAccounts.NFT with the given Address as a NonFungibleToken.NFT, emitting standard 
        /// Withdraw event along with RemovedLinkedAccount event, denoting the delegated access for the account
        /// associated with the NFT has been removed from this Collection
        ///
        /// @param address: The Address associated with the requested NFT
        ///
        /// @return The requested LinkedAccounts.NFT as a NonFungibleToken.NFT
        ///
        pub fun withdrawByAddress(address: Address): @NonFungibleToken.NFT {
            // Get the id of the assocated NFT
            let id: UInt64 = self.getIDOfLinkedAccountNFT(ofAddress: address)
                ?? panic("This Collection does not contain an NFT associated with the given address ".concat(address.toString()))
            // Withdraw & return the NFT
            return <- self.withdraw(withdrawID: id)
        }

        /** --- CollectionPublic --- */
        //
        /// Returns an array of all child account addresses
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
        /// @param ofAddress: Address associated with the desired LinkedAccounts.NFT
        ///
        /// @return The id of the associated LinkedAccounts.NFT or nil if it does not exist in this Collection
        ///
        pub fun getIDOfLinkedAccountNFT(ofAddress: Address): UInt64? {
            let addressToIDRef = &self.addressToID as &{Address: UInt64}
            return addressToIDRef[ofAddress]
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

        /// Allows the Collection to retrieve a reference to the NFT for a specified child account address
        ///
        /// @param address: The Address of the child account
        ///
        /// @return the reference to the child account's ChildAccountTag
        ///
        pub fun borrowLinkedAccountNFT(address: Address): &LinkedAccounts.NFT? {
            let addressToIDRef = &self.addressToID as &{Address: UInt64}
            if let id: UInt64 = addressToIDRef[address] {
                // Create an authorized reference to allow downcasting
                let ref = (&self.ownedNFTs[id] as auth &NonFungibleToken.NFT?)!
                return ref as! &LinkedAccounts.NFT
            }
            return nil
        }

        /// Returns a reference to the specified linked account's AuthAccount
        ///
        /// @param address: The address of the relevant linked account
        ///
        /// @return the linked account's AuthAccount as ephemeral reference or nil if the
        ///         address is not of a linked account
        ///
        pub fun getChildAccountRef(address: Address): &AuthAccount? {
            if let ref = self.borrowLinkedAccountNFT(address: address) {
                return ref.getAuthAcctRef()
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
        pub fun getHandlerRef(address: Address): &Handler? {
            if let ref = self.borrowLinkedAccountNFT(address: address) {
                return ref.getHandlerRef()
            }
            return nil
        }

        // TODO: NFT refactor
        /// Add an existing account as a linked account to this Collection. This would be done in either a multisig
        /// transaction or by the linking account linking & publishing its AuthAccount Capability for the Collection's
        /// owner.
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

        // TODO: NFT refactor
        /// Adds the given Capability to the AccountHandler at the provided Address
        ///
        /// @param to: Address which is the key for the AccountHandler Cap
        /// @param cap: Capability to be added to the AccountHandler
        ///
        pub fun addCapability(to: Address, _ cap: Capability) {
            pre {
                self.addressToID.containsKey(to):
                    "No linked account NFT with given Address!"
            }
            // Get ref to handler
            let handlerRef = self.getHandlerRef(
                    address: to
                ) ?? panic("Problem with AccountHandler Capability for given address: ".concat(to.toString()))
            let capType: Type = cap.getType()
            
            // Pass the Capability to the linked account via the handler & emit
            handlerRef.grantCapability(cap)
            emit LinkedAccountGrantedCapability(parent: self.owner!.address, child: to, capabilityType: capType)
        }

        // TODO: NFT refactor
        /// Removes the capability of the given type from the AccountHandler with the given Address
        ///
        /// @param from: Address indexing the AccountHandler Capability
        /// @param type: The Type of Capability to be removed from the AccountHandler
        ///
        pub fun removeCapability(from: Address, type: Type) {
            pre {
                self.addressToID.containsKey(from):
                    "No linked account with given Address!"
            }
            // Get ref to handler and remove
            let handlerRef = self.getHandlerRef(
                    address: from
                ) ?? panic("Problem with AccountHandler Capability for given address: ".concat(from.toString()))
            // Revoke Capability & emit
            handlerRef.revokeCapability(type)
                ?? panic("Capability not properly revoked")
            emit CapabilityRevokedFromLinkedAccount(parent: self.owner!.address, child: from, capabilityType: type)
        }

        // TODO: NFT refactor
        /// Remove Handler, returning its Address if it exists.
        /// Note, removing a Handler does not revoke key access linked account if it has been added. This should be
        /// done in the same transaction in which this method is called.
        ///
        /// @param withAddress: The Address of the linked account to remove from the mapping
        ///
        /// @return the Address of the account removed or nil if it wasn't linked to begin with
        ///
        pub fun removeLinkedAccount(withAddress: Address): Address? {
            if let owner: @NFT <-self.linkedAccounts.remove(key: withAddress) {
                let ownerID = owner.id
                // Get a reference to the AccountHandler from the Capability
                let handlerRef = owner.getHandlerRef()
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
                    "Attempting to destroy Colleciton with remaining NFTs!"
            }
            destroy self.ownedNFTs
        }
        
    }

    /// Helper method to determine if a public key is active on an account by comparing the given key against all keys
    /// active on the given account.
    ///
    /// @param publicKey: A public key as a string
    /// @param address: The address of the 
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

    /* --- NonFungibleToken --- */
    //
    /// Returns a new Collection
    ///
    pub fun createEmptyCollection(): @NonFungibleToken.Collection {
        emit CollectionCreated()
        return <-create Collection()
    }

    /* --- ViewResolver --- */
    //
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
                    storagePath: LinkedAccounts.CollectionStoragePath,
                    publicPath: LinkedAccounts.CollectionPublicPath,
                    providerPath: LinkedAccounts.CollectionPrivatePath,
                    publicCollection: Type<&LinkedAccounts.Collection{LinkedAccounts.CollectionPublic}>(),
                    publicLinkedType: Type<&LinkedAccounts.Collection{LinkedAccounts.CollectionPublic, NonFungibleToken.CollectionPublic, NonFungibleToken.Receiver, MetadataViews.ResolverCollection}>(),
                    providerLinkedType: Type<&LinkedAccounts.Collection{LinkedAccounts.CollectionPublic, NonFungibleToken.CollectionPublic, NonFungibleToken.Provider, MetadataViews.ResolverCollection}>(),
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
        self.CollectionStoragePath = /storage/LinkedAccountCollection
        self.CollectionPublicPath = /public/LinkedAccountCollection
        self.CollectionPrivatePath = /private/LinkedAccountCollection
        // Assign AccountHandler paths
        self.HandlerStoragePath = /storage/LinkedAccountHandler
        self.HandlerPublicPath = /public/LinkedAccountHandler
        self.HandlerPrivatePath = /private/LinkedAccountHandler

        emit ContractInitialized()
    }
}
 