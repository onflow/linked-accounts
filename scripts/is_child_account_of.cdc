import ChildAccount from "../contracts/ChildAccount.cdc"

/// This script allows one to determine if a given account is a child 
/// account of the specified parent account as the parent-child account
/// relationship is defined in the ChildAccount contract
///
pub fun main(parent: Address, child: Address): Bool {

    // Get a reference to the ChildAccountManagerViewer in parent's account
    if let viewerRef = getAccount(parent).getCapability<
            &{ChildAccount.ChildAccountManagerViewer}
        >(ChildAccount.ChildAccountManagerPublicPath).borrow() {
        // If the given child address is one of the parent's children account, check if it's active
        if viewerRef.getChildAccountAddresses().contains(child) {
            if let childAccountTagPublicRef = getAccount(child).getCapability<
                    &ChildAccount.ChildAccountTag{ChildAccount.ChildAccountTagPublic}
                >(ChildAccount.ChildAccountTagPublicPath).borrow() {

                return childAccountTagPublicRef.isCurrentlyActive()
            }
        }
    }
    
    return false
}
 