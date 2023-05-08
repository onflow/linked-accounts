import LinkedAccounts from "../../contracts/LinkedAccounts.cdc"
import FlowToken from "../../contracts/utility/FlowToken.cdc"
import FungibleToken from "../../contracts/utility/FungibleToken.cdc"
import MetadataViews from "../../contracts/utility/MetadataViews.cdc"

/// This transaction creates an account, funding creation via the signer and
/// adding the provided public key. You'll notice this transaction is pretty
/// much your standar account creation. The magic for you will be how you custody
/// the key for this account (locally, KMS, wallet service, etc.) in a manner that
/// allows your dapp to mediate on-chain interactions on behalf of your user.
/// **NOTE:** Custodial patterns have regulatory implications you'll want to consult a 
/// legal professional about.
///
/// In your dapp's walletless transaction, you'll likely also want to configure
/// the new account with resources & capabilities relevant for your use case after
/// account creation & optional funding.
///
transaction(
    pubKey: String,
    initialFundingAmt: UFix64,
  ) {
	
	prepare(signer: AuthAccount) {

		/* --- Account Creation (your dApp may choose to separate creation depending on your custodial model) --- */
		//
		// Create the child account, funding via the signer
		let newAccount = AuthAccount(payer: signer)
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

		/* --- (Optional) Additional Account Funding --- */
		//
		// Fund the new account if specified
		if initialFundingAmt > 0.0 {
			// Get a vault to fund the new account
			let fundingProvider = signer.borrow<&FlowToken.Vault{FungibleToken.Provider}>(
					from: /storage/flowTokenVault
				)!
			// Fund the new account with the initialFundingAmount specified
			newAccount.getCapability<&FlowToken.Vault{FungibleToken.Receiver}>(
				/public/flowTokenReceiver
			).borrow()!
			.deposit(
				from: <-fundingProvider.withdraw(
					amount: initialFundingAmt
				)
			)
		}

		/* Continue with use case specific setup */
		//
		// At this point, the newAccount can further be configured as suitable for
		// use in your dapp (e.g. Setup a Collection, Mint NFT, Configure Vault, etc.)
		// ...
	}
}