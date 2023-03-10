import ChildAccount from "../../contracts/ChildAccount.cdc"

/// Sets up a ChildAccountManager in signer's account to enable management
/// of linked accounts via AuthAccount Capabilities
///
transaction {
    prepare(signer: AuthAccount) {
        // Return early if already configured
        if signer.borrow<&ChildAccount.ChildAccountManager>(from: ChildAccount.ChildAccountManagerStoragePath) == nil {
            signer.save(
                <-ChildAccount.createChildAccountManager(),
                to: ChildAccount.ChildAccountManagerStoragePath
            )
        }
        // Link the public Capability
        if !signer.getCapability<
                &ChildAccount.ChildAccountManager{ChildAccount.ChildAccountManagerViewer}
            >(ChildAccount.ChildAccountManagerPublicPath).check() {
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