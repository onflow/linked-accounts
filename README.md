# Linked Accounts

> :warning: This repo is reflective of the iteration outlined in [this FLIP](https://github.com/onflow/flips/pull/72) and currently implemented in the [Walletless Arcade demo](https://walletless-arcade-game.vercel.app/). Implementation details should be taken as experimental without expectation that this code will it to production in its current form. Collaborative work is underway on the `HybridCustody` contract suite in [this repo](https://github.com/Flowtyio/restricted-child-account), which will serve as the basis for Hybrid Custody on Flow moving forward.

This repository contains the `LinkedAccounts` contracts along with supporting scripts & transactions related to linking accounts 
in support of [walletless onboarding](https://flow.com/post/flow-blockchain-mainstream-adoption-easy-onboarding-wallets)
and the [hybrid custody account model](https://forum.onflow.org/t/hybrid-custody/4016/15).

### Contract Addresses
**v1 Testnet (`ChildAccount`)**: [0x1b655847a90e644a](https://f.dnz.dev/0x1b655847a90e644a/ChildAccount)
**v2 Testnet (`LinkedAccounts`)**: [0x1b655847a90e644a](https://f.dnz.dev/0x1b655847a90e644a/LinkedAccounts)

## Linked accounts In Practice
Check out the [@onflow/sc-eng-gaming repo](https://github.com/onflow/sc-eng-gaming/blob/sisyphusSmiling/child-account-auth-acct-cap/contracts/RockPaperScissorsGame.cdc) to see how the `LinkedAccounts` Cadence suite works in the context of a Rock, Paper, Scissors game.

More details on building on this Cadence suite for interoperable hybrid custody in your dApp can be found in the [Account Linking Developer Portal](https://developers.flow.com/account-linking).