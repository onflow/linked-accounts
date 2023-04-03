# Linked Accounts

> This repo is reflective of the design proposed in [this FLIP](https://github.com/onflow/flips/pull/72) and the contained implementation on the main branch will be updated to reflect common consensus on a contract standard for linked account management.

This repository contains the `LinkedAccounts` contracts along with supporting scripts & transactions related to linking accounts 
in support of [walletless onboarding](https://flow.com/post/flow-blockchain-mainstream-adoption-easy-onboarding-wallets)
and the [hybrid custody account model](https://forum.onflow.org/t/hybrid-custody/4016/15).

### Contract Addresses
**v1 Testnet (`ChildAccount`)**: [0x1b655847a90e644a](https://f.dnz.dev/0x1b655847a90e644a/ChildAccount)
**v2 Testnet (`LinkedAccounts`)**: TBD

## Linked accounts In Practice
Check out the [@onflow/sc-eng-gaming repo](https://github.com/onflow/sc-eng-gaming/blob/sisyphusSmiling/child-account-auth-acct-cap/contracts/RockPaperScissorsGame.cdc) to see how the `LinkedAccounts` Cadence suite works in the context of a Rock, Paper, Scissors game.

More details on building on this Cadence suite for interoperable hybrid custody in your dApp can be found in the [Account Linking Developer Portal](https://developers.flow.com/account-linking).