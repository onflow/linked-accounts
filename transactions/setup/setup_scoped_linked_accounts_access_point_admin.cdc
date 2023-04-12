import ScopedLinkedAccounts from "../../contracts/ScopedLinkedAccounts.cdc"

/// Sets up a LinkedAccounts.AccessPointAdmin in signer's account enabling them to create AccessPoints and unrestrict
/// created AccessPoints
///
transaction {
    prepare(signer: AuthAccount) {
        // Check if an AccessPointAdmin is saved in storage
        if signer.type(at: ScopedLinkedAccounts.CollectionStoragePath) == nil {
            // If not, create and save the AccessPointAdmin in canonical StoragePath
            signer.save(
                <-ScopedLinkedAccounts.createAccessPointAdmin(),
                to: ScopedLinkedAccounts.AccessPointAdminStoragePath
            )
        }
    }
}
