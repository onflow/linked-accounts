pub contract ScopedAccounts {

    pub let AccessPointStoragePath: StoragePath
    pub let AccessPointPrivatePath: PrivatePath

    pub struct interface CapabilityValidator {
        pub fun validate(expectedType: Type, capability: Capability): Bool
    }

    pub resource interface AccessPointPublic {
        pub fun getID(): UInt64
        pub fun getAllowedCapabilities(): {Type: CapabilityPath}
    }

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

        // pub fun getViews(): [Type]
        // pub fun resolveView(_ view: Type): AnyStruct?

        access(self) fun borrowAuthAccount(): &AuthAccount {
            return self.authAccountCapability.borrow() ?? panic("Problem with AuthAccount Capability")
        }
    }
    
    init() {
        self.AccessPointStoragePath = /storage/AccessPoint
        self.AccessPointPrivatePath = /private/AccessPoint
    }
}
