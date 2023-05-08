import LinkedAccounts from "../contracts/LinkedAccounts.cdc"

pub fun main(pubKeyString: String, address: Address): Bool {
    return LinkedAccounts.isKeyActiveOnAccount(publicKey: pubKeyString, address: address)
}