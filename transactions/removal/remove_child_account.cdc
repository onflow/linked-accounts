import LinkedAccounts from "../../contracts/LinkedAccounts.cdc"

/// This transaction removes access to a linked account from the signer's LinkedAccounts Collection.
/// **NOTE:** The signer will no longer have access to the removed child account via AuthAccount Capability, so care
/// should be taken to ensure any assets in the child account have been first transferred as well as checking active
/// keys that need to be revoked have been done so (a detail that will largely depend on you dApps custodial model)
///
transaction(childAddress: Address) {

    let collectionRef: &LinkedAccounts.Collection
    
    prepare(signer: AuthAccount) {
        // Assign a reference to signer's LinkedAccounts.Collection
        self.collectionRef = signer.borrow<&LinkedAccounts.Collection>(
                from: LinkedAccounts.CollectionStoragePath
            ) ?? panic("Signer does not have a LinkedAccounts Collection configured!")
    }

    execute {
        // Remove child account, revoking any granted Capabilities
        self.collectionRef.removeLinkedAccount(withAddress: childAddress)
    }
}
 