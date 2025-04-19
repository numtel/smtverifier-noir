use dep::smt;

global N : u32 = 160;

// TODO prove first item in smt
// TODO prove item value update in smt
// Prove that an item did not exist and that adding it caused the root to change like this
fn main(root : pub Field, key : Field, value : Field, siblings : [Field; N], missingKey : Field, missingKey2 : Field, missingValue : Field, afterRoot : pub Field) {
    smt::verifier::verifyExclusion(root, key, value, siblings, missingKey);
    // The matching item from the exclusion proof becomes the new item's last sibling
    let newSibling : Field = std::hash::poseidon::bn254::hash_3([key, value, 1]);
    let mut afterSiblings : [Field; N] = [0; N];
    for i in 0..N {
        if siblings[i] != 0 {
            afterSiblings[i] = siblings[i];
            if siblings[i + 1] == 0 {
                afterSiblings[i + 1] = newSibling;
            }
        }
    }
    // XXX Why do I have to assert this value?
    assert(missingKey == missingKey2);
    // The final root reflects the added item
    smt::verifier::verify(afterRoot, missingKey2, missingValue, afterSiblings);
}
