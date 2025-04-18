import os from 'node:os';
import { UltraHonkBackend } from '@aztec/bb.js';
import { Noir } from '@noir-lang/noir_js';

import { SMT } from "@cedoor/smt";
import { poseidon2, poseidon3 } from 'poseidon-lite';

// cd example && noir compile
import compiledCircuit from "./target/smtverifier_example.json" with { type: "json" };

const noir = new Noir(compiledCircuit);
const backend = new UltraHonkBackend(compiledCircuit.bytecode, { threads: os.cpus().length });

async function testSmtProof(smtProof) {
  // Inpus shared between both types of proofs
  const inputs = {
    root: smtProof.root.toString(10),
    siblings: [
      ...smtProof.sidenodes.map(x=>x.toString(10)),
      // siblings must match the array length in example/src/main.nr (160)
      ...Array(160 - smtProof.sidenodes.length).fill("0")
    ],
  };
  // Different values for proving included in set vs excluded from set
  if(smtProof.membership) {
    // Inclusion proof
    inputs.key = smtProof.entry[0].toString(10);
    inputs.value = smtProof.entry[1].toString(10);
    inputs.missingKey = 0; // no missing key with a proof of inclusion
  } else {
    // Exclusion proof
    inputs.key = smtProof.matchingEntry[0].toString(10);
    inputs.value = smtProof.matchingEntry[1].toString(10);
    inputs.missingKey = smtProof.entry[0].toString(10);
  }
  const { witness } = await noir.execute(inputs);
  const { proof, publicInputs } = await backend.generateProof(witness);

  // Verify proof
  return await backend.verifyProof({ proof, publicInputs });
}

(async () => {
  try {
    // Build a Sparse Merkle Tree using the same hashing as the circuit
    const tree = new SMT(childNodes => {
      // end leaf value
      if(childNodes.length === 3) return poseidon3(childNodes);
      // else, intermediate leaf value
      return poseidon2(childNodes);
    }, true);

    // Put some entries in it
    for(let i=1n; i<1000n; i+=5n) {
      tree.add(i, i*2n);
    }

    // Test inclusion proof
    console.time('Inclusion proof generation');
    const verified1 = await testSmtProof(tree.createProof(11n));
    console.timeEnd('Inclusion proof generation');
    console.log('Inclusion proof verified', verified1);
    // Test non-inclusion proof
    console.time('Exclusion proof generation');
    const verified2 = await testSmtProof(tree.createProof(122n));
    console.timeEnd('Exclusion proof generation');
    console.log('Exclusion proof verified', verified2);

    process.exit(verified1 && verified2 ? 0 : 1);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
})();
