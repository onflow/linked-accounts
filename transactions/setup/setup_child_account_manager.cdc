import ChildAccount from "../../contracts/ChildAccount.cdc"

/// Sets up a ChildAccountManager in signer's account to enable management
/// of linked accounts via AuthAccount Capabilities
///
transaction {
    prepare(signer: AuthAccount) {
        // Check for ChildAccountManager in storage
        if signer.borrow<&ChildAccount.ChildAccountCreator>(from: ChildAccount.ChildAccountCreatorStoragePath) == nil {
            // Create one
            signer.save(
                <-ChildAccount.createChildAccountCreator(),
                to: ChildAccount.ChildAccountCreatorStoragePath
            )
        }
        // Check for public Capability
        if !signer.getCapability<
                &ChildAccount.ChildAccountManager{ChildAccount.ChildAccountManagerViewer}
            >(ChildAccount.ChildAccountManagerPublicPath).check() {
            // Link the ChildAccountManagerViewer Public Capability
            signer.unlink(ChildAccount.ChildAccountManagerPublicPath)
            signer.link<
                &ChildAccount.ChildAccountManager{ChildAccount.ChildAccountManagerViewer}
            >(
                ChildAccount.ChildAccountManagerPublicPath,
                target: ChildAccount.ChildAccountManagerStoragePath
            )
        }
    }
}