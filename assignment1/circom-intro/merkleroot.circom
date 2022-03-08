pragma circom 2.0.0;

include "mimcsponge.circom";

/* This circuit takes a list of numbers input as leaves of a Merkle tree and outputs the Merkle root.  */
template MerkleRoot (n) {
  signal input leaves[n];
  signal output root;
  // create an array of components equal to tree size
  component comp[2*n-1];

  // hash the leaves first, 1 input each
  for (var i = 0; i < n; i++) {
    comp[i] = MiMCSponge(1, 220, 1);
    comp[i].k <== 0;
    comp[i].ins[0] <== leaves[i];
  }

  // tracks nodes in current level
  var nodesInLevel = n;
  // tracks offset for two leaf nodes to use to generate hash
  var offset = 0;
  while (nodesInLevel > 0) {
    for (var i = 0; i < nodesInLevel - 1; i += 2) {
      // 2 inputs are used per hash
      comp[i/2 + offset + nodesInLevel] = MiMCSponge(2, 220, 1);
      comp[i/2 + offset + nodesInLevel].k <== 0;
      // sets inputs as hash function output of the two relevant nodes
      comp[i/2 + offset + nodesInLevel].ins[0] <== comp[i + offset].outs[0];
      comp[i/2 + offset + nodesInLevel].ins[1] <== comp[i + offset + 1].outs[0];
    }
    // increase offset by nodes in level where we just finished computing the hash
    offset += nodesInLevel;
    // as we go up the tree, nodes in next level are halved
    nodesInLevel = nodesInLevel/2;    
  }
  // root node is stored in last item of array
  root <== comp[2*n-2].outs[0];

}

component main { public [leaves] } = MerkleRoot(8);