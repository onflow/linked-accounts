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
    pub let AccessPointStoragePath: StoragePath
    pub let AccessPointPrivatePath: PrivatePath

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
            self.id = self.uuid
            self.authAccountCapability = authAccountCapability
            self.allowedCapabilities = allowedCapabilities
            self.validator = validator
        }

        pub fun getAllowedCapabilities(): {Type: CapabilityPath} {
            return self.allowedCapabilities
        }

        pub fun getScopedAccountAddress(): Address {
            return self.borrowAuthAcccount().address
        }

        pub fun getCapabilityByType(_ type: Type): Capability? {
            if self.allowedCapabilities.containsKey(type) {
                let account: &AuthAccount = self.borrowAuthAcccount()
                let cap: Capability = account.getCapability(
                    self.allowedCapabilitiesp[type]!
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

        access(self) fun borrowAuthAccount(): &AuthAccount {
            return self.authAccountCapability.borrow() ?? panic("Problem with AuthAccount Capability")
        }
    }
    
    init() {
        self.AccessPointStoragePath = /storage/ScopedAccountsAccessPoint
        self.AccessPointPrivatePath = /private/ScopedAccountsAccessPoint
    }
}
