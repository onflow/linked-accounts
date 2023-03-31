import { expect } from "@jest/globals";
import { executeScript } from "@onflow/flow-js-testing";
import { getCollectionIDs } from "./script_templates";

// Asserts whether length of account's collection matches
// the expected collection length
export async function assertCollectionLength(account, expectedCollectionLength) {
    const [collectionIDs, e] = await executeScript(
        "game_piece_nft/get_collection_ids",
        [account]
    );
    expect(e).toBeNull();
    expect(collectionIDs.length).toBe(expectedCollectionLength);
};

// Asserts whether the NFT corresponding to the id is in address's collection
export async function assertNFTInCollection(address, id) {
    const ids = await getCollectionIDs(address);
    expect(ids.includes(id.toString())).toBe(true);
};
