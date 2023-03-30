import ExampleNFT from "../../contracts/utility/ExampleNFT.cdc"
import ScopedAccounts from "../../contracts/ScopedAccounts.cdc"

/// Claims an AccessPoint Capability from the given provider, storing it at the specified StoragePath
///
transaction(capabilityName: String,capabilityProvider: Address) {

    prepare(signer: AuthAccount) {
        // Claim the Capability
        let accessPointCap: Capability<&ScopedAccounts.AccessPoint> = signer.inbox.claim<&ScopedAccounts.AccessPoint>(
                capabilityName,
                provider: capabilityProvider
            ) ?? panic("No AccessPoint Capability available from provider with given name!")
        // Store the AccessPoint Capability
        signer.save(
            <-ScopedAccounts.createAccessor(accessPointCapability: accessPointCap),
            to: ScopedAccounts.AccessorStoragePath
        )
    }
}
 