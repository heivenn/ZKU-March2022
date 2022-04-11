// light client
// EpochData includes epoch index, public key of validators, signature threshold
EpochData genesisEpochData;
EpochData latestEpochData; 
// ProofOfCommitteeTransition includes initial epoch, epoch updates, aggregated signature of all validators over all epoch changes
ProofOfCommitteeTransition proofs[]; // stores all proofs ever submitted
function updateState(proofOfTransition) external onlyRelayers {
  verify(proofOfTransition); // call verify contract generated from circuit
  updateState(proofOfTransition.output); // updates latestEpochData
  proofs.push(proofOfTransition);
}

// proof circuit generates proof of committee transition from epoch X to epoch Y
inputs: epoch indices X & Y, committee (BLS public keys) of epoch i
for each epoch block from X to Y:
  aggregate validator public keys from block header using bitmap
  check quorum is more than 2/3 signature threshold 
  check epoch index is next epoch
  encode epoch to bits and use Blake2S hash to group element
  compute and verify BLS signature with aggregated public keys and aggregated signature
  increase epoch index
output: proof of committee transition from epoch X to Y

