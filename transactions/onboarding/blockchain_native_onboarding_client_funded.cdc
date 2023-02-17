import ChildAccount from "../contracts/ChildAccount.cdc"
import MetadataViews from "../contracts/utility/MetadataViews.cdc"

/// This transaction creates an account using the client's ChildAccountCreator,
/// funding creation via the signing account and adding the provided public key.
/// A ChildAccountTag resource is saved in the new account, identifying it as an
/// account created under this construction. This resource also holds metadata
/// related to the purpose of this account.
/// Additionally, the ChildAccountCreator maintains a mapping of addresses created
/// by it indexed on the originatingpublic key. This enables dapps to lookup the
/// address for which they hold a public key. 
///
transaction(
    pubKey: String,
    fundingAmt: UFix64,
    childAccountName: String,
    childAccountDescription: String,
    clientIconURL: String,
    clientExternalURL: String
  ) {

	let managerRef: &ChildAccount.ChildAccountManager
    let info: ChildAccount.ChildAccountInfo
    let childAccountCap: Capability<&AuthAccount>
	let newAccountAddress: Address
	
	prepare(parent: AuthAccount, client: AuthAccount) {
		
		/* --- Get a ChildAccountCreator reference from client's account --- */
		//
		// Save a ChildAccountCreator if none exists
		if client.borrow<&ChildAccount.ChildAccountCreator>(from: ChildAccount.ChildAccountCreatorStoragePath) == nil {
			client.save(<-ChildAccount.createChildAccountCreator(), to: ChildAccount.ChildAccountCreatorStoragePath)
		}
		// Link the public Capability so signer can query address on public key
		if !client.getCapability<
				&ChildAccount.ChildAccountCreator{ChildAccount.ChildAccountCreatorPublic}
			>(ChildAccount.ChildAccountCreatorPublicPath).check() {
			// Link Cap
			client.unlink(ChildAccount.ChildAccountCreatorPublicPath)
			client.link<
				&ChildAccount.ChildAccountCreator{ChildAccount.ChildAccountCreatorPublic}
			>(
				ChildAccount.ChildAccountCreatorPublicPath,
				target: ChildAccount.ChildAccountCreatorStoragePath
			)
		}
		// Get a reference to the ChildAccountCreator
		let creatorRef = client.borrow<&ChildAccount.ChildAccountCreator>(
				from: ChildAccount.ChildAccountCreatorStoragePath
			) ?? panic("Problem getting a ChildAccountCreator reference!")
		
		/* --- Create the new account --- */
		//
		// Construct the ChildAccountInfo metadata struct
		self.info = ChildAccount.ChildAccountInfo(
			name: childAccountName,
			description: childAccountDescription,
			clientIconURL: MetadataViews.HTTPFile(url: clientIconURL),
			clienExternalURL: MetadataViews.ExternalURL(clientExternalURL),
			originatingPublicKey: pubKey
			)
		// Create the account, passing signer AuthAccount to fund account creation
		// and add initialFundingAmount in Flow if desired
		let newAccount: AuthAccount = creatorRef.createChildAccount(
			signer: client,
			initialFundingAmount: fundingAmt,
			childAccountInfo: info
			)
		self.newAccountAddress = newAccount.address
		// At this point, the newAccount can further be configured as suitable for
		// use in your dapp (e.g. Setup a Collection, Mint NFT, Configure Vault, etc.)
		// ...

		/* --- Setup parent's ChildAccountManager --- */
		//
		// Check the parent account for a ChildAccountManager
        if parent.borrow<
				&ChildAccount.ChildAccountManager
			>(from: ChildAccount.ChildAccountManagerStoragePath) == nil {
            // Save a ChildAccountManager to the signer's account
            parent.save(<-ChildAccount.createChildAccountManager(), to: ChildAccount.ChildAccountManagerStoragePath)
        }
        // Ensure ChildAccountManagerViewer is linked properly
        if !parent.getCapability<
                &ChildAccount.ChildAccountManager{ChildAccount.ChildAccountManagerViewer}
            >(ChildAccount.ChildAccountManagerPublicPath).check() {
            // Link Cap
			parent.unlink(ChildAccount.ChildAccountManagerPublicPath)
            parent.link<
                &ChildAccount.ChildAccountManager{ChildAccount.ChildAccountManagerViewer}
            >(
                ChildAccount.ChildAccountManagerPublicPath,
                target: ChildAccount.ChildAccountManagerStoragePath
            )
        }
        // Get ChildAccountManager reference from signer
        self.managerRef = parent.borrow<
                &ChildAccount.ChildAccountManager
            >(from: ChildAccount.ChildAccountManagerStoragePath)!
		// Link the new account's AuthAccount Capability
		self.childAccountCap = newAccount.linkAccount(ChildAccount.AuthAccountCapabilityPath)
		
	}

	execute {
		/* --- Link the parent & child accounts --- */
		//
		// Add account as child to the ChildAccountManager
        self.managerRef.addAsChildAccount(childAccountCap: self.childAccountCap, childAccountInfo: self.info)
	}

	post {
		// Make sure new account was linked to parent's successfully
		self.managerRef.getChildAccountAddresses().contains(self.newAccountAddress):
			"Problem linking accounts!"
	}
}
