import os from 'node:os';
import { UltraHonkBackend } from '@aztec/bb.js';
import { Noir } from '@noir-lang/noir_js';

import { SMT } from "@cedoor/smt";
import { poseidon2, poseidon3 } from 'poseidon-lite';

// To generate this file, run command: $ nargo compile --package smtverifier_example_state_transition
import compiledCircuit from "../target/smtverifier_example_state_transition.json" with { type: "json" };

const noir = new Noir(compiledCircuit);
const backend = new UltraHonkBackend(compiledCircuit.bytecode, { threads: os.cpus().length });

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
    tree.add(1n,12n);
    tree.add(2n,13n);

    // Test proving that there was a valid state change from one root to another
    // by adding an item to the tree
    // TODO prove first item in smt
    // TODO prove item value update in smt
    const toAddKey = 12n;
    const toAddValue = 1234n;
    const proofBefore = tree.createProof(toAddKey);
    tree.add(toAddKey, toAddValue);
    const proofAfter = tree.createProof(toAddKey);

    const inputs = {
      root: proofBefore.root.toString(10),
      siblings: [
        ...proofBefore.sidenodes.map(x=>x.toString(10)),
        // siblings must match the array length in ./src/main.nr (160)
        ...Array(160 - proofBefore.sidenodes.length).fill("0")
      ],
      key: proofBefore.matchingEntry[0].toString(10),
      value: proofBefore.matchingEntry[1].toString(10),
      // XXX Why does this have to be duplicated to avoid that error?
      // "Error: Index out of bounds, array has size 160, but index was 253"
      // Some kind of strange constraint magic
      missingKey: toAddKey.toString(10),
      missingKey2: toAddKey.toString(10),
      missingValue: toAddValue.toString(10),
      afterRoot: proofAfter.root.toString(10),
    };

    // Test inclusion proof
    console.time('Proof generation');
    const { witness } = await noir.execute(inputs);
    const { proof, publicInputs } = await backend.generateProof(witness);
    console.timeEnd('Proof generation');

    // Verify proof
    const verified = await backend.verifyProof({ proof, publicInputs });
    console.log('Proof verified', verified);

    process.exit(verified ? 0 : 1);
  } catch (error) {
    console.error(error);
    process.exit(1);
  }
})();

