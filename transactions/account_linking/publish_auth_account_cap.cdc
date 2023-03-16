#allowAccountLinking

/// Signing account publishes a Capability to its AuthAccount for
/// the specified parentAddress to claim
///
transaction(parentAddress: Address, authAccountPathSuffix: String) {

    let authAccountCap: Capability<&AuthAccount>

    prepare(signer: AuthAccount) {
        // Assign the PrivatePath where we'll link the AuthAccount Capability
        let authAccountPath: PrivatePath = PrivatePath(identifier: authAccountPathSuffix)
            ?? panic("Could not construct PrivatePath from given suffix: ".concat(authAccountPathSuffix))
        // Get the AuthAccount Capability, linking if necessary
        if !signer.getCapability<&AuthAccount>(authAccountPath).check() {
            signer.unlink(authAccountPath)
            self.authAccountCap = signer.linkAccount(authAccountPath)!
        } else {
            self.authAccountCap = signer.getCapability<&AuthAccount>(authAccountPath)
        }
        // Publish for the specified Address
        signer.inbox.publish(self.authAccountCap!, name: "AuthAccountCapability", recipient: parentAddress)
    }
}