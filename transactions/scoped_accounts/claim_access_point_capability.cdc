import ExampleNFT from "../../contracts/utility/ExampleNFT.cdc"
import ScopedAccounts from "../../contracts/ScopedAccounts.cdc"

/// Claims an AccessPoint Capability from the given provider, storing it at the specified StoragePath
///
transaction(
    capabilityName: String,
    capabilityProvider: Address,
    capabilityStoragePathIdentifier: String
    ) {

    prepare(signer: AuthAccount) {
        // Claim the Capability
        let accessPointCap: Capability<&ScopedAccounts.AccessPoint> = signer.inbox.claim<&ScopedAccounts.AccessPoint>(
                capabilityName,
                provider: capabilityProvider
            ) ?? panic("No AccessPoint Capability available from provider with given name!")
        // Construct the StoragePath where we'll store the Capability
        let capabilityStoragePath: StoragePath = StoragePath(identifier: capabilityStoragePathIdentifier)
            ?? panic("Could not construct Storage path from given identifier: ".concat(capabilityStoragePathIdentifier))
        // Store the AccessPoint Capability
        signer.save(accessPointCap, to: capabilityStoragePath)
    }
}
