/// Proof of concept AuthAccount Capability wrapping resource that allows the creator to define the Capabilities Types
/// and corresponding paths able to retrieved from the wrapped account. To enforce a path's corresponding Capability
/// Type, each AccessPoint maintains a generic CapabilityValidator which ensures that a given Capability matches its
/// expected type.
///
/// Implementers should define conditions for matching type based on the Capabilities they will allow in a wrapping
/// AccessPoint such that the Validator returns truthfully.
///
pub contract ScopedAccounts {

    /* Canonical Paths */
    //
    // AccessPoint
    pub let AccessPointStoragePath: StoragePath
    pub let AccessPointPublicPath: PublicPath
    pub let AccessPointPrivatePath: PrivatePath
    pub let AccessorStoragePath: StoragePath

    /* Events */
    //
    pub event AccessPointCreated(id: UInt64, address: Address, allowedCapabilityTypes: [Type])

    /* --- CapabilityValidator --- */
    //
    /// An interface defining a struct that validates that a given generic Capability returns a reference of the 
    /// given expected Type
    ///
    pub struct interface CapabilityValidator {
        pub fun validate(expectedType: Type, capability: Capability): Bool
    }

    /* --- AccessPoint --- */
    //
    pub resource interface AccessPointPublic {
        pub fun getID(): UInt64
        pub fun getAllowedCapabilities(): {Type: CapabilityPath}
        pub fun getScopedAccountAddress(): Address
    }

    /// A wrapper around an AuthAccount Capability which enforces retrieval of specified Types from specified 
    /// CapabilityPaths
    ///
    pub resource AccessPoint : AccessPointPublic {
        access(self) let id: UInt64
        access(self) let authAccountCapability: Capability<&AuthAccount>
        access(self) let allowedCapabilities: {Type: CapabilityPath}
        access(self) let validator: AnyStruct{CapabilityValidator}

        init(
            authAccountCapability: Capability<&AuthAccount>,
            allowedCapabilities: {Type: CapabilityPath},
            validator: AnyStruct{CapabilityValidator}
        ) {
            pre {
                authAccountCapability.check(): "Problem with provided AuthAccount Capability"
            }
            self.id = self.uuid
            self.authAccountCapability = authAccountCapability
            self.allowedCapabilities = allowedCapabilities
            self.validator = validator
        }

        pub fun getID(): UInt64 {
            return self.id
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
        
        // TODO-?: Batch retrieve Capabilities
        // pub fun getCapabilitiesByType(_ types: [Type]): {Type: Capability}

        // TODO-?: Impl MetadataViews.ResolverCollection ??
        // pub fun getViews(): [Type]
        // pub fun resolveView(_ view: Type): AnyStruct?

        /// Helper method to return a reference the associated AuthAccount
        ///
        access(self) fun borrowAuthAccount(): &AuthAccount {
            return self.authAccountCapability.borrow() ?? panic("Problem with AuthAccount Capability")
        }
    }

    /* --- Accessor --- */
    //
    /// Wrapper for the AccessPoint Capability
    ///
    pub resource Accessor {
        /// The UUID for the AccessPoint this Accessor is designed to access
        access(self) let accessPointUUID: UInt64
        /// Capability to an AccessPoint
        access(self) var accessPointCapability: Capability<&AccessPoint>
        
        init(accessPointCapability: Capability<&AccessPoint>) {
            pre {
                accessPointCapability.check():
                    "Problem with provided AccessPoint Capability!"
            }
            self.accessPointCapability = accessPointCapability
            self.accessPointUUID = accessPointCapability.borrow()!.uuid
        }

        /// Simple getter for the stored AccessPoint Capability
        ///
        pub fun getAccessPointCapability(): Capability<&AccessPoint> {
            pre {
                self.accessPointCapability.check():
                    "Problem with stored AccessPoint Capability!"
                self.accessPointCapability.borrow()!.uuid == self.accessPointUUID:
                    "Underlying AccessPoint resource has been changed!"
            }
            return self.accessPointCapability
        }

        /// Getter for the Address of the account this Accessor is able to access
        ///
        pub fun getAccessibleAccount(): Address {
            return self.borrowAccessPoint().getScopedAccountAddress()
        }

        /// Allows caller to retrieve reference to the AccessPoint for which a Capability is stored
        ///
        pub fun borrowAccessPoint(): &AccessPoint {
            pre {
                self.accessPointCapability.check():
                    "Problem with stored AccessPoint Capability!"
                self.accessPointCapability.borrow()!.uuid == self.accessPointUUID:
                    "Underlying AccessPoint resource has been changed!"
            }
            return self.accessPointCapability.borrow()!
        }

        /// Enables caller to swap the stored AccessPoint Capability for another
        ///
        pub fun swapAccessPointCapability(_ new: Capability<&AccessPoint>) {
            pre {
                new.check():
                    "Problem with provided AccessPoint Capability!"
                new.borrow()!.uuid == self.accessPointUUID:
                    "Provided a Capability for an AccessPoint different than this Accessor was originally given!"
            }
            self.accessPointCapability = new
        }
    }

    /// Creates a new AccessPoint resource
    ///
    pub fun createAccessPoint(
        authAccountCapability: Capability<&AuthAccount>,
        allowedCapabilities: {Type: CapabilityPath},
        validator: AnyStruct{CapabilityValidator}
    ): @AccessPoint {
        let accessPoint <-create AccessPoint(
            authAccountCapability: authAccountCapability,
            allowedCapabilities: allowedCapabilities,
            validator: validator
        )
        emit AccessPointCreated(id: accessPoint.getID(), address: authAccountCapability.borrow()!.address, allowedCapabilityTypes: allowedCapabilities.keys)
        return <-accessPoint
    }

    /// Creates a new Accessor resource, wrapping the provided AccessPoint Capability
    ///
    pub fun createAccessor(accessPointCapability: Capability<&AccessPoint>): @Accessor {
        return <-create Accessor(accessPointCapability: accessPointCapability)
    }
    
    init() {
        self.AccessPointStoragePath = /storage/ScopedAccountsAccessPoint
        self.AccessPointPublicPath = /public/ScopedAccountsAccessPoint
        self.AccessPointPrivatePath = /private/ScopedAccountsAccessPoint
        self.AccessorStoragePath = /storage/ScopedAccountsAccessor
    }
}
 