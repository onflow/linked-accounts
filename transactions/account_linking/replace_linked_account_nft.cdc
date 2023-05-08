#allowAccountLinking
import NonFungibleToken from "../../contracts/utility/NonFungibleToken.cdc"
import LinkedAccountMetadataViews from "../../contracts/LinkedAccountMetadataViews.cdc"
import LinkedAccounts from "../../contracts/LinkedAccounts.cdc"

/// This transaction will replace the linked account NFT's AuthAccount Capability with a new one at the specified 
/// PrivatePath which would be useful in the event of a compromised AuthAccount Capability path or if the signer is
/// concerned about secondary access post-transfer. 
///
/// **NOTE:** Of course, this transaction only considered access mediated by AuthAccount Capability, not keys which
/// might be a concern depending on the linked account's custodial model.
///
transaction(
    address: Address,
    newAuthAccountCapPathSuffix: String,
    oldAuthAccountCapPathSuffix: String?
) {

    let newAccountCap: Capability<&AuthAccount>

    prepare(signer: AuthAccount) {
        
        // Get a reference to the signer's Collection
        let collectionRef: &LinkedAccounts.Collection = signer.borrow<&LinkedAccounts.Collection>(
                from: LinkedAccounts.CollectionStoragePath
            ) ?? panic("Signer does not have a LinkedAccount.Collection configured at expected path!")
        // Withdraw LinkedAccounts.NFT
        let nft: @LinkedAccounts.NFT <-collectionRef.withdrawByAddress(address: address) as! @LinkedAccounts.NFT
        
        // Get the linked account's AuthAccount reference
        let linkedAccountRef: &AuthAccount = nft.borrowAuthAcccount()
        
        // Construct a PrivatePath for the new AuthAccount Capability link
        let newAuthAccountCapPath = PrivatePath(identifier: newAuthAccountCapPathSuffix)
            ?? panic("Could not create PrivatePath from provided suffix: ".concat(newAuthAccountCapPathSuffix))
        // Assign the new AuthAccount Capability
        if !linkedAccountRef.getCapability<&AuthAccount>(newAuthAccountCapPath).check() {
            linkedAccountRef.unlink(newAuthAccountCapPath)
            self.newAccountCap = linkedAccountRef.linkAccount(newAuthAccountCapPath)
                ?? panic(
                    "Problem linking AuthAccount Capability at :"
                    .concat(linkedAccountRef.address.toString())
                    .concat("/")
                    .concat(newAuthAccountCapPath.toString()))
        } else {
            self.newAccountCap = linkedAccountRef.getCapability<&AuthAccount>(newAuthAccountCapPath)
        }
        
        // Update the AuthAccount Capability
        nft.updateAuthAccountCapability(self.newAccountCap)
        // register the new linked account address so it can be deposited
        collectionRef.addPendingDeposit(address: self.newAccountCap.address)
        
        // Unlink old AuthAccount Capability if path suffix is specified
        if oldAuthAccountCapPathSuffix != nil {
            let oldAuthAccountCapPath = PrivatePath(identifier: newAuthAccountCapPathSuffix)
                ?? panic("Could not create PrivatePath from provided suffix: ".concat(oldAuthAccountCapPathSuffix!))
            linkedAccountRef.unlink(oldAuthAccountCapPath)
        }
        
        // Deposit the NFT back to Collection
        collectionRef.deposit(token: <-nft)
    }
}
