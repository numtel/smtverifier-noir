use dep::smt;

fn main(root : pub Field, key : Field, value : Field, siblings : [Field; 160], missingKey : Field) {
    if missingKey != 0 {
        smt::verifier::verifyExclusion(root, key, value, siblings, missingKey);
    } else {
        smt::verifier::verify(root, key, value, siblings);
    }
}
