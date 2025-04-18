use crate::helpers;

pub fn verify<let N: u32>(root : Field, key : Field, value : Field, siblings : [Field; N]) {
    verifyExtended(1, root, 0, 0, 0, key, value, 0, siblings);
}

pub fn verifyExclusion<let N: u32>(root : Field, key : Field, value : Field, siblings : [Field; N], missingKey : Field) {
    verifyExtended(1, root, 0, 0, 0, key, value, 0, siblings);

    let keyBits : [u1; N] = key.to_le_bits();
    let missingKeyBits : [u1; N] = missingKey.to_le_bits();

    let mut matchingBits : u32 = 0;
    let mut siblingLength : u32 = 0;
    for i in 0..N {
        if (keyBits[i] != missingKeyBits[i]) & (matchingBits == 0) {
            matchingBits = i;
        }
        if (siblings[i] == 0) & (siblingLength == 0) {
            siblingLength = i;
        }
    }
    // special cases for complete misses
    if keyBits[0] != missingKeyBits[0] {
        matchingBits = 0;
    }
    if (siblings[0] == 0) {
        siblingLength = 0;
    }

    // From https://github.com/cedoor/sparse-merkle-tree/blob/f345e2f53603f36701564aedc2f6106d9ce17d35/src/smt.ts#L266
    // If the non-member key was a key of a tree entry, the depth of the
    // matching node should be greater than the number of the first common
    // bits of the keys. The depth of a node can be defined by the number
    // of its side nodes.
    assert(siblingLength <= matchingBits);
}

#[field(bn254)]
fn verifyExtended<let N: u32>(enabled : Field, root : Field, oldKey : Field, oldValue : Field, 
    isOld0 : Field, key : Field, value : Field, fnc : Field, siblings : [Field; N]) {
    // Steps:
	//   1. Get the hash of both key-value pairsold and new one.
	//   2. Get the binary representation of the key new.
	//   3. Get the path of the current key.
	//   4. Calculate the root with the siblings provided.
	//   5. Compare the calculated root with the provided one.
	let hash1Old = helpers::endLeafValue(oldKey, oldValue);
	let hash1New = helpers::endLeafValue(key, value);

    let n2bNew : [u1; 254] = key.to_le_bits(); // REVIEW: Fixed bit len

    let levIns = levelIns(siblings, if enabled == 1 { true } else { false });

    let mut stTops : [Field; N] = [0; N];
    let mut stIolds : [Field; N] = [0; N];
    let mut stI0s : [Field; N] = [0; N];
    let mut stInews : [Field; N] = [0; N];
    let mut stNas : [Field; N] = [0; N];
	for i in 0..N {
        let (stTop, stInew, stIold, stI0, stNa) = if i == 0 {
            smVerifier(isOld0, levIns[0], fnc, enabled, 0, 0, 0, 1 - enabled)
        } else {
            smVerifier(isOld0, levIns[i], fnc, stTops[i-1], stI0s[i-1], 
                stIolds[i-1], stInews[i-1], stNas[i-1])
        };
        stTops[i] = stTop;
        stInews[i] = stInew;
        stIolds[i] = stIold;
        stI0s[i] = stI0;
        stNas[i] = stNa;
	}

    assert(stNas[N-1] + stIolds[N-1] + stInews[N-1] + 
        stI0s[N-1] == 1);

    let mut levels : [Field; N] = [0; N];
    let mut i = N-1;
    for n in 0..N {
        levels[i] = levelVerifier(stTops[i], stInews[i], stIolds[i], siblings[i],
            hash1Old, hash1New, n2bNew[i] as u1, if n != 0 { levels[i+1] } else { 0 });
        i -= 1;
    }

    let areKeyEquals = if oldKey == key { 1 } else { 0 };
	assert(helpers::multiAnd([fnc, 1 - isOld0, areKeyEquals, enabled]) == 0);
    assert(root == levels[0]);
}

fn levelIns<let N: u32>(siblings : [Field; N], enabled : bool) -> [Field; N] {
    if enabled {
        assert(siblings[siblings.len()-1] == 0);
    }

    let isZero = siblings.map(|i| if i == 0 { 1 } else { 0 });
    let mut isDone : [Field; N] = [0; N];
    let mut levIns : [Field; N] = [0; N];
    
    let last = 1 - isZero[siblings.len()-2];
    levIns[siblings.len()-1] = last;
    isDone[siblings.len()-2] = last;

    for n in 2..siblings.len() {
        let i = siblings.len()-n;
        levIns[i] = (1 - isDone[i]) * (1 - isZero[i-1]);
        isDone[i-1] = levIns[i] + isDone[i];
    }
    levIns[0] = 1 - isDone[0];
    levIns
}

fn smVerifier(is0 : Field, levIns : Field, fnc : Field, prevTop : Field, prevI0 : Field, 
    prevIold : Field, prevInew : Field, prevNa : Field) -> (Field, Field, Field, Field, Field) {
	let prevTopLevIns = prevTop * levIns;
	let prevTopLevInsFnc = prevTopLevIns * fnc;
	let stTop = prevTop - prevTopLevIns;
	let stInew = prevTopLevIns - prevTopLevInsFnc;
	let stIold = prevTopLevInsFnc * (1 - is0);
	let stI0 = prevTopLevIns * is0;
	let stNa = prevNa + prevInew + prevIold + prevI0;
    (stTop, stInew, stIold, stI0, stNa)
}

fn levelVerifier(stTop : Field, stInew : Field, stIold : Field, sibling : Field, 
    old1leaf : Field, new1leaf : Field, lrbit : u1, child : Field) -> Field {
    let (l, r) = helpers::switcher(lrbit, child, sibling);
    (helpers::intermediateLeafValue(l, r) * stTop) + (old1leaf * stIold) + 
        (new1leaf * stInew)
}

#[test]
#[field(bn254)]
fn test_verify() {
    let root = 21135506078746510573119705753579567335835726524098367527812922933644667691006;
    let key = 500400244448261235194511589700085192056257072811;
    let value = 10;
    let siblings : [Field; 8] = [
        13175438946403099127785287940793227584022396513432127658229341995655669945927,
		8906855681626013805208515602420790146700990181185755277830603493975762067087,
		9457781280074316365191154663065840032069867769247887694941521931147573919101,
		3886003602968045687040541715852317767887615077999207197223340281752527813105,
		5615297718669932502221460377065820025799135258753150375139282337562917282190,
		8028805327216345358010190706209509799652032446863364094962139617192615346584,
		572541247728029242828004565014369314635015057986897745288271497923406188177,
		9738042754594087795123752255236264962836518315799343893748681096434196901468,
    ];
    let mut totalSiblings : [Field; 160] = [0; 160];
    for i in 0..siblings.len() {
        totalSiblings[i] = siblings[i];
    }
    verify(root, key, value, totalSiblings);
}

#[test]
#[field(bn254)]
fn test_verifyExclusion() {
    // Using an smt proof from the javascript example
    let root = 5618324597502323820885345800277144982196263183590633505771983039653247749960;
    let key = 506;
    let value = 1012;
    let siblings : [Field; 7] = [
        14615338145095048680177242786365678259101023300950869524449924128481796206177,
        8295645616626971682119455512805556469242627149482378721206534435609843398038,
        12319462714305072733723151337482443799987337263634426352504845778782439563661,
        19810871284681492549135357010988661891244092017826449908651988317222360591701,
        11550320017336065025539478515962585018659991473644200644857132467517785025312,
        13088179057460137001052606589737535980431054338677162412216742731749484268261,
        16887208525207770201881780564842279686650971548585408198642541617619782767413,
    ];
    let mut totalSiblings : [Field; 160] = [0; 160];
    for i in 0..siblings.len() {
        totalSiblings[i] = siblings[i];
    }
    verifyExclusion(root, key, value, totalSiblings, 122);
}

#[test]
fn test_levelIns() {
    let siblings: [Field; 10] = [ 10, 4, 3, 2, 1, 0, 0, 0, 0, 0 ];
    let res = levelIns(siblings, true);
    assert(res[0] == 0);
    assert(res[1] == 0);
    assert(res[2] == 0);
    assert(res[3] == 0);
    assert(res[4] == 0);
    assert(res[5] == 1);
    assert(res[6] == 0);
    assert(res[7] == 0);
    assert(res[8] == 0);
    assert(res[9] == 0);
}

#[test]
fn test_smVerifier() {
    let (stTop, stInew, stIold, stI0, stNa) = smVerifier(1, 1, 1, 1, 1, 1, 1, 1);
    assert(stTop == 0);
    assert(stInew == 0);
    assert(stIold == 0);
    assert(stI0 == 1);
    assert(stNa == 4);
}

#[test]
#[field(bn254)]
fn test_levelVerifier() {
    let res = 7853200120776062878684798364095072458815029376092732009249414926327459813532;
    assert(levelVerifier(1, 1, 1, 2, 1, 1, 0, 1) == res);
}
