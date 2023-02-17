import MetadataViews from "../contracts/utility/MetadataViews.cdc"
import ChildAccount from "../contracts/ChildAccount.cdc"

/// Links thie signing accounts as labeled, with the child's AuthAccount Capability
/// maintained in the parent's ChildAccountManager resource.
/// Assumes that the child account has ChildAccountTag configured, as would be
/// the case if created by ChildAccountCreator.
///
transaction {

    let authAccountCap: Capability<&AuthAccount>
    let managerRef: &ChildAccount.ChildAccountManager
    let info: ChildAccount.ChildAccountInfo
    let childAccountAddress: Address

    prepare(parent: AuthAccount, child: AuthAccount) {
        
        /* --- Configure parent's ChildAccountManager --- */
        //
        // Get ChildAccountManager Capability, linking if necessary
        if parent.borrow<&ChildAccount.ChildAccountManager>(from: ChildAccount.ChildAccountManagerStoragePath) == nil {
            // Save
            parent.save(<-ChildAccount.createChildAccountManager(), to: ChildAccount.ChildAccountManagerStoragePath)
        }
        // Ensure ChildAccountManagerViewer is linked properly
        if !parent.getCapability<
                &ChildAccount.ChildAccountManager{ChildAccount.ChildAccountManagerViewer}
            >(ChildAccount.ChildAccountManagerPublicPath).check() {
            // Link
            parent.unlink(ChildAccount.ChildAccountManagerPublicPath)
            parent.link<
                &ChildAccount.ChildAccountManager{ChildAccount.ChildAccountManagerViewer}
            >(
                ChildAccount.ChildAccountManagerPublicPath,
                target: ChildAccount.ChildAccountManagerStoragePath
            )
        }
        // Get a reference to the ChildAccountManager resource
        self.managerRef = parent.borrow<
                &ChildAccount.ChildAccountManager
            >(from: ChildAccount.ChildAccountManagerStoragePath)!

        /* --- Link the child account's AuthAccount Capability & assign --- */
        //
        // Get the AuthAccount Capability, linking if necessary
        if !child.getCapability<&AuthAccount>(ChildAccount.AuthAccountCapabilityPath).check() {
            // Unlink any Capability that may be there
            child.unlink(ChildAccount.AuthAccountCapabilityPath)
            // Link & assign the AuthAccount Capability
            self.authAccountCap = child.linkAccount(ChildAccount.AuthAccountCapabilityPath)!
        } else {
            // Assign the AuthAccount Capability
            self.authAccountCap = child.getCapability<&AuthAccount>(ChildAccount.AuthAccountCapabilityPath)
        }

        // Get the child account's Metadata which should have been configured on creation by ChildAccountCreator
        let childTagRef = child.borrow<
                &ChildAccount.ChildAccountTag
            >(from: ChildAccount.ChildAccountTagStoragePath)
            ?? panic("Could not borrow reference to ChildAccountTag in account ".concat(child.address.toString()))
        self.info = childTagRef.info
        self.childAccountAddress = child.address
    }

    execute {
        // Add child account if it's parent-child accounts aren't already linked
        let childAddress = self.authAccountCap.borrow()!.address
        if !self.managerRef.getChildAccountAddresses().contains(childAddress) {
            // Add the child account
            self.managerRef.addAsChildAccount(childAccountCap: self.authAccountCap, childAccountInfo: self.info)
        }
    }

    post {
        self.managerRef.getChildAccountAddresses().contains(childAccountAddress):
            "Problem linking accounts!"
    }
}
