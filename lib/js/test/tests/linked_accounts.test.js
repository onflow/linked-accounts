import path from "path";
import { expect } from "@jest/globals";
import { 
  emulator, 
  init, 
  getAccountAddress, 
  deployContractByName, 
  sendTransaction, 
  shallPass,
  shallRevert,
  executeScript,
  mintFlow,
  createAccount,
  PublicKey
} from "@onflow/flow-js-testing";
import fs from "fs";
import { exec } from "child_process";
import { createPublicKey } from "crypto";


// Auxiliary function for deploying the cadence contracts
async function deployContract(param) {
  const [result, error] = await deployContractByName(param);
  if (error != null) {
    console.log(`Error in deployment - ${error}`);
    emulator.stop();
    process.exit(1);
  }
}

describe("Walletless onboarding", ()=>{

  // Variables for holding the account address
  let serviceAccount;
  let devAccount;
  let parentAccount;

  // Before each test...
  beforeEach(async () => {
    // We do some scaffolding...

    // Getting the base path of the project
    const basePath = path.resolve(__dirname, "./../../../../"); 
		// You can specify different port to parallelize execution of describe blocks
    const port = 8080; 
		// Setting logging flag to true will pipe emulator output to console
    const logging = false;

    await init(basePath);
    await emulator.start({ logging });

    // ...then we deploy the ft and example token contracts using the getAccountAddress function
    // from the flow-js-testing library...

    // Create a service account and deploy contracts to it
    serviceAccount = await getAccountAddress("ServiceAccount");
    await mintFlow(serviceAccount, 10000000.0);

    await deployContract({ to: serviceAccount, name: "utility/FungibleToken" });
    await deployContract({ to: serviceAccount, name: "utility/NonFungibleToken" });
    await deployContract({ to: serviceAccount, name: "utility/MetadataViews" });
    await deployContract({ to: serviceAccount, name: "utility/ViewResolver" });
    await deployContract({ to: serviceAccount, name: "utility/FungibleTokenMetadataViews" });
    await deployContract({ to: serviceAccount, name: "LinkedAccountMetadataViews" });
    await deployContract({ to: serviceAccount, name: "LinkedAccounts" });

    // Create a developer account and fund with Flow
    devAccount = await getAccountAddress("DevAccount");
    await mintFlow(devAccount, 10000000.0);

    // Create a parent account that will emulate the wallet-connected account
    parentAccount = await getAccountAddress("ParentAccount");
    await mintFlow(parentAccount, 100.0);

  });

  // After each test we stop the emulator, so it could be restarted
  afterEach(async () => {
    return emulator.stop();
  });

  // Test walletless onboarding transaction passes
  test("Dev account should create & fund new account for walletless onboarding", async () => {
    // Submit walletless onboarding transaction
    let pubKey = "eb986126679b4b718208c9d1d92f5b357f46137fe8de2f5bc589b0c5dfc3e8812f256faea8c6719d1ee014e1b08c62d2243af1413dfb6c2cbf36aca229eb5d05";
    await shallPass(
      sendTransaction({
        name: "onboarding/walletless_onboarding_signer_funded",
        args: [ pubKey, 10.0 ],
        signers: [ devAccount ]
      })
    );
  });

  // Test blockchain-native onboarding transaction passes
  test("Dev account should create & fund new account for blockchain-native onboarding, linking new account to parent", async () => {
    // Query the parent account's linked accounts before linking a newly created account
    let [linkedAccountsBefore, err1] = await executeScript(
        "get_linked_account_addresses",
        [parentAccount]
      );
    // Results should be be null
    expect(linkedAccountsBefore).toBeNull();
    expect(err1).toBeNull();
    
    // Submit blockchain native onboarding transaction
    let pubKey = "eb986126679b4b718208c9d1d92f5b357f46137fe8de2f5bc589b0c5dfc3e8812f256faea8c6719d1ee014e1b08c62d2243af1413dfb6c2cbf36aca229eb5d05";
    let [onboardingResult, err2] = await shallPass(
      sendTransaction({
        name: "onboarding/blockchain_native_onboarding_client_funded",
        args: [
          pubKey,
          10.0,
          "Test Name",
          "Test description",
          "thumbnailURL.com/img.jpg",
          "thumbnailURL.com",
          "TestAuthAccountCapability",
          "TestHandler"
        ],
        signers: [ parentAccount, devAccount ]
      })
    );
    expect(err2).toBeNull();

    // Query the parent account's linked accounts after linking the new account
    let [linkedAccountsAfter, err3] = await executeScript(
      "get_linked_account_addresses",
      [parentAccount]
    );
    let childAccountAddress = linkedAccountsAfter[0];
    expect(linkedAccountsAfter.length).toEqual(1);
    expect(err3).toBeNull();

    // Confirm listed child account address is actively linked to parent account
    let [isChildAccount, err4] = await executeScript(
      "is_child_account_of",
      [parentAccount, childAccountAddress]
    );
    expect(isChildAccount).toBe(true);
    expect(err4).toBeNull();

    // Ensure public key is active on child account
    let [isKeyActive, err5] = await executeScript(
      "is_key_active_on_account",
      [ pubKey, childAccountAddress ]
    );
    expect(isKeyActive).toBe(true);
    expect(err5).toBeNull()
  });

  // Link existing account with parent account
  test("Link accounts", async () => {
    // Get the existing child account
    let childAccount = await getAccountAddress("childAccount");
    // Query the parent account's linked accounts before linking a newly created account
    let [ linkedAccountsBefore, err1 ] = await executeScript(
      "get_linked_account_addresses",
      [parentAccount]
    );
    // Results should be be null
    expect(linkedAccountsBefore).toBeNull();
    expect(err1).toBeNull();
    // Link the parent & child accounts
    let [linkResult, err2] = await shallPass(
      sendTransaction({
        name: "account_linking/add_as_child_multisig",
        args: [
          "Test Name",
          "Test description",
          "thumbnailURL.com/img.jpg",
          "thumbnailURL.com",
          "TestAuthAccountCapability",
          "TestHandler"
        ],
        signers: [ parentAccount, childAccount ]
      })
    );
    expect(err2).toBeNull();

    // Query the parent account's linked accounts after linking the new account
    let [ linkedAccountsAfter, err3 ] = await executeScript(
      "get_linked_account_addresses",
      [parentAccount]
    );
    let childAccountAddress = linkedAccountsAfter[0];
    expect(linkedAccountsAfter.length).toEqual(1);
    expect(err3).toBeNull();

    // Confirm listed child account address is actively linked to parent account
    let [ isChildAccount, err4 ] = await executeScript(
      "is_child_account_of",
      [ parentAccount, childAccountAddress ]
    );
    expect(isChildAccount).toBe(true);
    expect(err4).toBeNull();
  });

  /**
   * TODO:
   * - Removing account
   * - Pending deposit (positive & negative cases)
   * - Accessing AuthAccount Cap by NFT reference fails
   * - Update AuthAccount Capability
   * - Replace linked account NFT (test old AA Cap)
   * - Query FT balance metadata
   * - Query LA metadata
   * - Add event confirmation
   */
});