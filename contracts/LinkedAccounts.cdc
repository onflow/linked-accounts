import NonFungibleToken from "./utility/NonFungibleToken.cdc"
import FungibleToken from "./utility/FungibleToken.cdc"
import FlowToken from "./utility/FlowToken.cdc"
import MetadataViews from "./utility/MetadataViews.cdc"
import LinkedAccountMetadataViews from "./LinkedAccountMetadataViews.cdc"

/// This contract is an attempt at establishing and representing a
/// parent-child hierarchy between linked accounts.
///
/// The LinkedAccountAdministrator allows a parent account to create child accounts, and
/// maintains a mapping of child accounts as they are created. An account is deemed 
/// a child of a parent if the parent maintains delegated access on the child
/// account by way of AuthAccount Capability stored in a LinkedAccountAdministrator. By the
/// constructs defined in this contract, a child account can be identified by a stored
/// LinkedAccountHandler.
///
/// While one generally would not want to share account access with other parties,
/// this can be helpful in a low-stakes environment where the parent account's owner
/// wants to delegate transaction signing to a secondary party. The idea for this setup
/// was born out of pursuit of a more seamless on-chain gameplay UX where a user could
/// let a game client submit transactions on their behalf without signing over the whole
/// of their primary account, and do so in a way that didn't require custom a Capability.
///
/// With that said, users should bear in mind that any assets in a child account incur
/// obvious custodial risk, and that it's generally an anti-pattern to pass around AuthAccounts.
/// In this case, a user owns both accounts so they are technically passing an AuthAccount
/// to themselves in calls to resources that reside in their own account, so it was deemed
/// a valid application of the pattern. That said, a user should be cognizant of the party
/// with key access on the child account as this pattern requires some degree of trust in the
/// custodying party.
///
pub contract LinkedAccounts {

    pub event AddedLinkedAccount(parent: Address, child: Address)
    pub event LinkedAccountGrantedCapability(parent: Address, child: Address, capabilityType: Type)
    pub event CapabilityRevokedFromLinkedAccount(parent: Address, child: Address, capabilityType: Type)
    pub event RemovedLinkedAccount(parent: Address, child: Address)
    pub event LinkedAccountAdministratorCreated()

    /* Standard paths */
    //
    pub let LinkedAccountAdministratorStoragePath: StoragePath
    pub let LinkedAccountAdministratorPublicPath: PublicPath
    pub let LinkedAccountAdministratorPrivatePath: PrivatePath
    pub let LinkedAccountHandlerStoragePath: StoragePath
    pub let LinkedAccountHandlerPublicPath: PublicPath
    pub let LinkedAccountHandlerPrivatePath: PrivatePath

    /** --- LinkedAccountHandler--- */
    //
    pub resource interface LinkedAccountHandlerPublic {
        access(contract) let parentAddress: Address
        access(contract) let address: Address
        access(contract) let metadata: AnyStruct{LinkedAccountMetadataViews.LinkedAccountMetadata}
        pub fun getParentAddress(): Address
        pub fun getLinkedAccountMetadata(): AnyStruct{LinkedAccountMetadataViews.LinkedAccountMetadata}
        pub fun getGrantedCapabilityTypes(): [Type]
        pub fun isCurrentlyActive(): Bool
    }

    /// Identifies an account as a child account and maintains info
    /// about its parent & association as well as Capabilities granted by
    /// its parent's LinkedAccountAdministrator
    ///
    pub resource LinkedAccountHandler : LinkedAccountHandlerPublic {
        /// Pointer to this account's parent account
        access(contract) let parentAddress: Address
        /// The address of the account where the LinkedAccountHandler resource resides
        access(contract) let address: Address
        /// Metadata about the purpose of this child account
        access(contract) let metadata: AnyStruct{LinkedAccountMetadataViews.LinkedAccountMetadata}
        /// Capabilities that have been granted by the parent account
        access(contract) let grantedCapabilities: {Type: Capability}
        /// Flag denoting whether link to parent is still active
        access(contract) var isActive: Bool

        init(
            parentAddress: Address,
            address: Address,
            metadata: AnyStruct{LinkedAccountMetadataViews.LinkedAccountMetadata}
        ) {
            self.parentAddress = parentAddress
            self.address = address
            self.metadata = metadata
            self.grantedCapabilities = {}
            self.isActive = true
        }

        /** --- LinkedAccountHandlerPublic --- */
        //
        /// Returns the Address of this linked account's parent LinkedAccountAdministrator
        ///
        pub fun getParentAddress(): Address {
            return self.parentAddress
        }
        
        /// Returns the metadata related to this account's association
        ///
        pub fun getLinkedAccountMetadata(): AnyStruct{LinkedAccountMetadataViews.LinkedAccountMetadata} {
            return self.metadata
        }

        /// Returns the types of Capabilities this Handler has been granted
        ///
        /// @return An array of the Types of Capabilities this resource has access to
        /// in its grantedCapabilities mapping
        ///
        pub fun getGrantedCapabilityTypes(): [Type] {
            return self.grantedCapabilities.keys
        }
        
        /// Returns whether the link between this Handler and its associated LinkedAccountAdministrator
        /// is still active - in practice whether the linked LinkedAccountAdministrator has removed
        /// this Handler's Capability
        ///
        pub fun isCurrentlyActive(): Bool {
            return self.isActive
        }

        /** --- LinkedAccountHandler --- */
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
        /// available
        ///
        pub fun getGrantedCapabilityAsRef(_ type: Type): &Capability? {
            pre {
                self.isActive: "LinkedAccountHandler has been de-permissioned by parent!"
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

    /// Wrapper for the linked account's metadata, AuthAccount, and LinkedAccountHandler Capabilities
    ///
    pub resource LinkedAccountOwner: NonFungibleToken.INFT, MetadataViews.Resolver {
        pub let id: UInt64
        /// The AuthAccount Capability for the linked account this LinkedAccountOwner represents
        access(self) let authAccountCapability: Capability<&AuthAccount>
        /// Capability for the relevant LinkedAccountHandler
        access(self) var handlerCapability: Capability<&LinkedAccountHandler>

        init(
            authAccountCap: Capability<&AuthAccount>,
            handlerCap: Capability<&LinkedAccountHandler>
        ) {
            self.id = self.uuid
            self.authAccountCapability = authAccountCap
            self.handlerCapability = handlerCap
        }

        /// Function that returns all the Metadata Views implemented by a LinkedAccountOwner
        ///
        /// @return An array of Types defining the implemented views. This value will be used by
        ///         developers to know which parameter to pass to the resolveView() method.
        ///
        pub fun getViews(): [Type] {
            let handlerRef: &LinkedAccounts.LinkedAccountHandler = self.handlerCapability.borrow()
                ?? panic("Problem with LinkedAccountHandler Capability in this LinkedAccountOwner")
            return [
                handlerRef.getLinkedAccountMetadata().getType()
            ]
        }

        /// Function that resolves a metadata view for this ChildAccount.
        ///
        /// @param view: The Type of the desired view.
        /// @return A structure representing the requested view.
        ///
        pub fun resolveView(_ view: Type): AnyStruct? {
            let handlerRef: &LinkedAccounts.LinkedAccountHandler = self.handlerCapability.borrow()
                ?? panic("Problem with LinkedAccountHandler Capability in this LinkedAccountOwner")
            // TODO: More view cases
            switch view {
                case handlerRef.getLinkedAccountMetadata().getType():
                    return handlerRef.getLinkedAccountMetadata()
                default:
                    return nil
            }
        }

        /// Get a reference to the child AuthAccount object.
        ///
        pub fun getAuthAcctRef(): &AuthAccount {
            return self.authAccountCapability.borrow() ?? panic("Problem with AuthAccount Capability in LinkedAccountOwner!")
        }

        /// Returns a reference to the LinkedAccountHandler
        ///
        pub fun getLinkedAccountHandlerRef(): &LinkedAccountHandler {
            return self.handlerCapability.borrow() ?? panic("Problem with LinkedAccountHandler Capability in LinkedAccountOwner!")
        }

        /// Returns a reference to the LinkedAccountHandler as LinkedAccountHandlerPublic
        ///
        pub fun getHandlerPublicRef(): &LinkedAccountHandler{LinkedAccountHandlerPublic} {
            return self.handlerCapability.borrow() ?? panic("Problem with LinkedAccountHandler Capability in LinkedAccountOwner!")
        }
    }

    /** --- LinkedAccountAdministrator --- */
    //
    /// Interface that allows one to view information about the owning account's
    /// child accounts including the addresses for all child accounts and information
    /// about specific child accounts by Address
    ///
    pub resource interface LinkedAccountAdministratorPublic {
        pub fun getLinkedAccountAddresses(): [Address]
        pub fun getOwnerIDFromAddress(address: Address): UInt64?
    }

    /// Resource allows for management of on-chain associations between accounts.
    /// Note that while creating child accounts is available in this resource,
    /// revoking keys on those child accounts is not.
    /// 
    pub resource LinkedAccountAdministrator : LinkedAccountAdministratorPublic, MetadataViews.ResolverCollection {

        pub let linkedAccounts: @{Address: LinkedAccountOwner}
        pub let idToAddress: {UInt64: Address}
        // pub let ownedNFTs: @{UInt64: NonFungibleToken.NFT}
        // pub let addressToID: {Address: UInt64}
        // let accountID = admin.addressToID[0x01]
        // let owner <-! admin.ownedNFTs[accountID]

        init() {
            self.linkedAccounts <- {}
            self.idToAddress = {}
        }

        /** --- LinkedAccountAdministratorPublic --- */
        //
        /// Returns an array of all child account addresses
        ///
        /// @return an array containing the Addresses of the linked accounts
        pub fun getLinkedAccountAddresses(): [Address] {
            return self.linkedAccounts.keys
        }

        /// Given an address, returns the id of the associated LinkedAccountOwner associated with
        /// the linked account
        ///
        /// @param address: The Address of the account in question
        ///
        /// @return the LinkedAccountOwner.id of the associated resource
        ///
        pub fun getOwnerIDFromAddress(address: Address): UInt64? {
            // Get a reference to the associated LinkedAccountOwner if exists & return its id
            if let ownerRef = &self.linkedAccounts[address] as &LinkedAccountOwner? {
                return ownerRef.id
            }
            return nil
        }
        
        /** --- MetadataViews.ResolverCollection--- */
        //
        /// Returns the IDs of the contained LinkedAccountOwner
        ///
        /// @return an array of the contained LinkedAccountOwner resources
        ///
        pub fun getIDs(): [UInt64] {
            return self.idToAddress.keys
        }

        /// Returns the LinkedAccountOwner as a Resolver for the specified ID
        ///
        /// @param id: The id of the LinkedAccountOwner
        ///
        /// @return A reference to the LinkedAccountOwner as a Resolver
        ///
        pub fun borrowViewResolver(id: UInt64): &{MetadataViews.Resolver} {
            pre {
                self.idToAddress.containsKey(id): "No LinkeAccountOwners with given ID"
            }
            // Get the address of the LinkedAccountOwner from the id
            let address = self.idToAddress[id]!
            // Return a reference as a Resolver
            return (&self.linkedAccounts[address] as! &{MetadataViews.Resolver}?)!
        }

        /** --- LinkedAccountAdministrator --- */
        //
        /// Returns a reference to the LinkedAccountOwner as a Resolver based on the given address
        ///
        /// @param address: The address of the linked account
        ///
        /// @return A reference to the LinkedAccountOwner as a Resolver
        ///
        pub fun borrowViewResolverFromAddress(address: Address): &{MetadataViews.Resolver} {
            pre {
                self.linkedAccounts.containsKey(address): "No LinkeAccountOwners with given Address"
            }
            // Return a reference as a Resolver
            return (&self.linkedAccounts[address] as! &{MetadataViews.Resolver}?)!
        }

        /// Allows the LinkedAccountAdministrator to retrieve a reference to the LinkedAccountOwner
        /// for a specified child account address
        ///
        /// @param address: The Address of the child account
        ///
        /// @return the reference to the child account's ChildAccountTag
        ///
        pub fun getLinkedAccountOwnerRef(address: Address): &LinkedAccountOwner? {
            return &self.linkedAccounts[address] as &LinkedAccountOwner?
        }

        /// Returns a reference to the specified linked account's AuthAccount
        ///
        /// @param address: The address of the relevant linked account
        ///
        /// @return the linked account's AuthAccount as ephemeral reference or nil if the
        /// address is not of a linked account
        ///
        pub fun getChildAccountRef(address: Address): &AuthAccount? {
            if let ownerRef = self.getLinkedAccountOwnerRef(address: address) {
                return ownerRef.getAuthAcctRef()
            }
            return nil
        }

        /// Returns a reference to the specified linked account's LinkedAccountHandler
        ///
        /// @param address: The address of the relevant linked account
        ///
        /// @return the child account's LinkedAccountHandler as ephemeral reference or nil if the
        /// address is not of a linked account
        ///
        pub fun getLinkedAccountHandlerRef(address: Address): &LinkedAccountHandler? {
            if let ownerRef = self.getLinkedAccountOwnerRef(address: address) {
                return ownerRef.getLinkedAccountHandlerRef()
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
            linkedAccountMetadata: AnyStruct{LinkedAccountMetadataViews.LinkedAccountMetadata},
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

            // Construct paths for the LinkedAccountHandler & its Capabilities
            let handlerStoragePath = StoragePath(identifier: handlerPathSuffix)
                ?? panic("Could not construct StoragePath for LinkedAccountHandler with given suffix")
            let handlerPublicPath = PublicPath(identifier: handlerPathSuffix)
                ?? panic("Could not construct PublicPath for LinkedAccountHandler with given suffix")
            let handlerPrivatePath = PrivatePath(identifier: handlerPathSuffix)
                ?? panic("Could not construct PrivatePath for LinkedAccountHandler with given suffix")

            // Create a LinkedAccountHandler
            let handler <-create LinkedAccountHandler(
                    parentAddress: parentAddress,
                    address: childAddress,
                    metadata: linkedAccountMetadata
                )
            // Save the LinkedAccountHandler in the child account's storage & link
            linkedAccountRef.save(<-handler, to: handlerStoragePath)
            // Ensure public Capability linked
            linkedAccountRef.link<&LinkedAccountHandler{LinkedAccountHandlerPublic}>(
                handlerPublicPath,
                target: handlerStoragePath
            )
            // Ensure private Capability linked
            linkedAccountRef.link<&LinkedAccountHandler>(
                handlerPrivatePath,
                target: handlerStoragePath
            )
            // Get a Capability to the linked LinkedAccountHandler Cap in linked account's private storage
            let handlerCap = linkedAccountRef
                .getCapability<&
                    LinkedAccountHandler
                >(
                    handlerPrivatePath
                )
            // Ensure the capability is valid before inserting it in administrator's linkedAccounts mapping
            assert(handlerCap.check(), message: "Problem linking LinkedAccountHandler Capability in new child account!")

            // Create a LinkedAccountOwner & insert to linkedAccounts mapping
            let owner <-create LinkedAccountOwner(
                    authAccountCap: linkedAccountCap,
                    handlerCap: handlerCap
                )
            
            // Add the id & owner to the relevant mappings
            self.idToAddress[owner.id] = childAddress
            self.linkedAccounts[childAddress] <-! owner

            emit AddedLinkedAccount(parent: parentAddress, child: childAddress)
        }

        /// Adds the given Capability to the LinkedAccountHandler at the provided Address
        ///
        /// @param to: Address which is the key for the LinkedAccountHandler Cap
        /// @param cap: Capability to be added to the LinkedAccountHandler
        ///
        pub fun addCapability(to: Address, _ cap: Capability) {
            pre {
                self.linkedAccounts.containsKey(to):
                    "No linked account with given Address!"
            }
            // Get ref to handler
            let handlerRef = self.getLinkedAccountHandlerRef(
                    address: to
                ) ?? panic("Problem with LinkedAccountHandler Capability for given address: ".concat(to.toString()))
            let capType: Type = cap.getType()
            
            // Pass the Capability to the linked account via the handler & emit
            handlerRef.grantCapability(cap)
            emit LinkedAccountGrantedCapability(parent: self.owner!.address, child: to, capabilityType: capType)
        }

        /// Removes the capability of the given type from the LinkedAccountHandler with the given Address
        ///
        /// @param from: Address indexing the LinkedAccountHandler Capability
        /// @param type: The Type of Capability to be removed from the LinkedAccountHandler
        ///
        pub fun removeCapability(from: Address, type: Type) {
            pre {
                self.linkedAccounts.containsKey(from):
                    "No linked account with given Address!"
            }
            // Get ref to handler and remove
            let handlerRef = self.getLinkedAccountHandlerRef(
                    address: from
                ) ?? panic("Problem with LinkedAccountHandler Capability for given address: ".concat(from.toString()))
            // Revoke Capability & emit
            handlerRef.revokeCapability(type)
                ?? panic("Capability not properly revoked")
            emit CapabilityRevokedFromLinkedAccount(parent: self.owner!.address, child: from, capabilityType: type)
        }

        /// Remove LinkedAccountHandler, returning its Capability if it exists. Note, doing so
        /// does not revoke key access linked account if it has been added. This should 
        /// be done in the same transaction in which this method is called.
        ///
        /// @param withAddress: The Address of the linked account to remove from the mapping
        ///
        /// @return the Address of the account removed or nil if it wasn't linked to begin with
        ///
        pub fun removeLinkedAccount(withAddress: Address): Address? {
            if let owner: @LinkedAccountOwner <-self.linkedAccounts.remove(key: withAddress) {
                let ownerID = owner.id
                // Get a reference to the LinkedAccountHandler from the Capability
                let handlerRef = owner.getLinkedAccountHandlerRef()
                // Set the handler as inactive
                handlerRef.setInactive()

                // Remove all capabilities from the LinkedAccountHandler
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
                self.linkedAccounts.length == 0:
                    "Attempting to destroy LinkedAccountAdministrator with remaining LinkedAccountOwners!"
            }
            destroy self.linkedAccounts
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

    /// Returns a new LinkedAccountAdministrator
    ///
    pub fun createLinkedAccountAdministrator(): @LinkedAccountAdministrator {
        emit LinkedAccountAdministratorCreated()
        return <-create LinkedAccountAdministrator()
    }

    init() {
        self.LinkedAccountAdministratorStoragePath = /storage/LinkedAccountAdministrator
        self.LinkedAccountAdministratorPublicPath = /public/LinkedAccountAdministrator
        self.LinkedAccountAdministratorPrivatePath = /private/LinkedAccountAdministrator

        self.LinkedAccountHandlerStoragePath = /storage/LinkedAccountHandler
        self.LinkedAccountHandlerPublicPath = /public/LinkedAccountHandler
        self.LinkedAccountHandlerPrivatePath = /private/LinkedAccountHandler
    }
}
