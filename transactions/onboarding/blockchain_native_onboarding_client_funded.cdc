#allowAccountLinking

import FungibleToken from "../../contracts/utility/FungibleToken.cdc"
import FlowToken from "../../contracts/utility/FlowToken.cdc"
import MetadataViews from "../../contracts/utility/MetadataViews.cdc"
import NonFungibleToken from "../../contracts/utility/NonFungibleToken.cdc"
import LinkedAccountMetadataViews from "../../contracts/LinkedAccountMetadataViews.cdc"
import LinkedAccounts from "../../contracts/LinkedAccounts.cdc"

/// This transaction creates an account, funding creation via the signing client account and adding the provided
/// public key (presumably custodied by the signing client/dApp). The new account then links a Capability to its
/// AuthAccount, and provides said Capability along with relevant LinkedAccountMetadataView.AccountInfo to
/// the signing parent account's LinkedAccounts.Collection, thereby giving the signing parent account access to the
/// new account.
/// After this transaction, both the custodial party (presumably the client/dApp) and the signing parent account will
/// have access to the newly created account - the custodial party via key access and the parent account via their
/// LinkedAccounts.Collection maintaining the new account's AuthAccount Capability.
///
transaction(
    pubKey: String,
    fundingAmt: UFix64,
    linkedAccountName: String,
    linkedAccountDescription: String,
    clientThumbnailURL: String,
    clientExternalURL: String,
    authAccountPathSuffix: String,
    handlerPathSuffix: String
  ) {

	let collectionRef: &LinkedAccounts.Collection
    let info: LinkedAccountMetadataViews.AccountInfo
    let authAccountCap: Capability<&AuthAccount>
	let newAccountAddress: Address
	
	prepare(parent: AuthAccount, client: AuthAccount) {
		
		/* --- Account Creation (your dApp may choose to handle creation differently depending on your custodial model) --- */
		//
		// Create the child account, funding via the client
		let newAccount = AuthAccount(payer: client)
		// Create a public key for the proxy account from string value in the provided arg
		// **NOTE:** You may want to specify a different signature algo for your use case
		let key = PublicKey(
			publicKey: pubKey.decodeHex(),
			signatureAlgorithm: SignatureAlgorithm.ECDSA_P256
		)
		// Add the key to the new account
		// **NOTE:** You may want to specify a different hash algo & weight best for your use case
		newAccount.keys.add(
			publicKey: key,
			hashAlgorithm: HashAlgorithm.SHA3_256,
			weight: 1000.0
		)

		/* (Optional) Additional Account Funding */
		//
		// Fund the new account if specified
		if fundingAmt > 0.0 {
			// Get a vault to fund the new account
			let fundingProvider = client.borrow<&FlowToken.Vault{FungibleToken.Provider}>(
					from: /storage/flowTokenVault
				)!
			// Fund the new account with the initialFundingAmount specified
			newAccount.getCapability<&FlowToken.Vault{FungibleToken.Receiver}>(
				/public/flowTokenReceiver
			).borrow()!
			.deposit(
				from: <-fundingProvider.withdraw(
					amount: fundingAmt
				)
			)
		}
		self.newAccountAddress = newAccount.address

		// At this point, the newAccount can further be configured as suitable for
		// use in your dapp (e.g. Setup a Collection, Mint NFT, Configure Vault, etc.)
		// ...

		/* --- Setup parent's LinkedAccounts.Collection --- */
		//
		// Check that Collection is saved in storage
        if parent.type(at: LinkedAccounts.CollectionStoragePath) == nil {
            parent.save(
                <-LinkedAccounts.createEmptyCollection(),
                to: LinkedAccounts.CollectionStoragePath
            )
        }
        // Link the public Capability
        if !parent.getCapability<
                &LinkedAccounts.Collection{NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, LinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}
            >(LinkedAccounts.CollectionPublicPath).check() {
            parent.unlink(LinkedAccounts.CollectionPublicPath)
            parent.link<&LinkedAccounts.Collection{NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic, LinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}>(
                LinkedAccounts.CollectionPublicPath,
                target: LinkedAccounts.CollectionStoragePath
            )
        }
        // Link the private Capability
        if !parent.getCapability<
                &LinkedAccounts.Collection{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic, LinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}
            >(LinkedAccounts.CollectionPrivatePath).check() {
            parent.unlink(LinkedAccounts.CollectionPrivatePath)
            parent.link<
                &LinkedAccounts.Collection{NonFungibleToken.Provider, NonFungibleToken.CollectionPublic, LinkedAccounts.CollectionPublic, MetadataViews.ResolverCollection}
            >(
                LinkedAccounts.CollectionPrivatePath,
                target: LinkedAccounts.CollectionStoragePath
            )
        }
		// Assign a reference to the Collection we now know is correctly configured
		self.collectionRef = parent.borrow<&LinkedAccounts.Collection>(from: LinkedAccounts.CollectionStoragePath)!

		/* --- Link the child account's AuthAccount Capability & assign --- */
        //
		// Assign the PrivatePath where we'll link the AuthAccount Capability
        let authAccountPath: PrivatePath = PrivatePath(identifier: authAccountPathSuffix)
            ?? panic("Could not construct PrivatePath from given suffix: ".concat(authAccountPathSuffix))
		// Link the new account's AuthAccount Capability
		self.authAccountCap = newAccount.linkAccount(authAccountPath)
			?? panic("Problem linking AuthAccount Capability in new account!")
		
		/** --- Construct metadata --- */
        //
        // Construct linked account metadata from given arguments
        self.info = LinkedAccountMetadataViews.AccountInfo(
            name: linkedAccountName,
            description: linkedAccountDescription,
            thumbnail: MetadataViews.HTTPFile(url: clientThumbnailURL),
            externalURL: MetadataViews.ExternalURL(clientExternalURL)
        )
	}

	execute {
		/* --- Link the parent & child accounts --- */
		//
		// Add the child account
		self.collectionRef.addAsChildAccount(
			linkedAccountCap: self.authAccountCap,
			linkedAccountMetadata: self.info,
			linkedAccountMetadataResolver: nil,
			handlerPathSuffix: handlerPathSuffix
		)
	}

	post {
		// Make sure new account was linked to parent's successfully
		self.collectionRef.getLinkedAccountAddresses().contains(self.newAccountAddress):
			"Problem linking accounts!"
	}
}
