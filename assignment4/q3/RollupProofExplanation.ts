// a recursive proof system is kind of like an "enum"
/*
 * Creates a child class of ProofWithInput, where RollupStateTransition is used as a public input in the proof
 * RollupProof has three branches (static methods) processDeposit, transaction and merge
 */
@proofSystem
class RollupProof extends ProofWithInput<RollupStateTransition> {
  // creates a proof that deposit has been processed and added to account tree
  @branch static processDeposit(
    pending: MerkleStack<RollupDeposit>,
    accountDb: AccountDb
  ): RollupProof {
    // initialize rollup state with the pending deposit and account commitment
    let before = new RollupState(pending.commitment, accountDb.commitment());
    // get the pending deposit: public key and amount, also
    let deposit = pending.pop();
    // use deposit public key to check of existence in account accumulator and create a membership proof
    let [{ isSome }, mem] = accountDb.get(deposit.publicKey);
    // an account should not exist - ensures the deposit hasn't been processed yet
    isSome.assertEquals(false);

    // Creates a new account with 0 balance and 0 nonce
    let account = new RollupAccount(
      UInt64.zero,
      UInt32.zero,
      deposit.publicKey
    );
    // adds account and membership proof (merkle proof and index) to the account accumulator
    accountDb.set(mem, account);
    // creates state with new deposit commitment and new account accumulator root
    let after = new RollupState(pending.commitment, accountDb.commitment());
    // returns an instance of RollupProof where its public input is the completed RollupStateTransition
    return new RollupProof(new RollupStateTransition(before, after));
  }

  // creates a proof that transaction has been processsed and added to account tree
  @branch static transaction(
    t: RollupTransaction,
    s: Signature,
    pending: MerkleStack<RollupDeposit>,
    accountDb: AccountDb
  ): RollupProof {
    // verify that signature is from sender
    s.verify(t.sender, t.toFields()).assertEquals(true);
    let stateBefore = new RollupState(
      pending.commitment,
      accountDb.commitment()
    );
    // gets sender account and merkle proof from tree
    let [senderAccount, senderPos] = accountDb.get(t.sender);
    // sender account exists
    senderAccount.isSome.assertEquals(true);
    // prevents duplicate transaction processing
    senderAccount.value.nonce.assertEquals(t.nonce);
    // deduct tx amount from sender balance
    senderAccount.value.balance = senderAccount.value.balance.sub(t.amount);
    // increase account nonce to indicate tx has been processed
    senderAccount.value.nonce = senderAccount.value.nonce.add(1);
    // updates sender account in the account tree
    accountDb.set(senderPos, senderAccount.value);

    // gets receiver account and merkle proof from tree
    let [receiverAccount, receiverPos] = accountDb.get(t.receiver);
    // increases receiver balance by tx amount
    receiverAccount.value.balance = receiverAccount.value.balance.add(t.amount);
    // updates receiver account in the account tree
    accountDb.set(receiverPos, receiverAccount.value);
    // creates after state with new tx commitment and new account accumulator root
    let stateAfter = new RollupState(
      pending.commitment,
      accountDb.commitment()
    );
    // returns an instance of RollupProof where its public input is the completed RollupStateTransition
    return new RollupProof(new RollupStateTransition(stateBefore, stateAfter));
  }
  // Combines proofs together to return a new rollup proof
  // if first proof proves that p1.source -> p1.target
  // and if second proof proves that p2.source -> p2.target
  // then if p1.target == p2.source, we can create a new proof where p1.source -> p2.target
  @branch static merge(p1: RollupProof, p2: RollupProof): RollupProof {
    // we can only do this if the first proof's target state is same as the second proof's initial state
    p1.publicInput.target.assertEquals(p2.publicInput.source);
    return new RollupProof(
      // creates new state where first proof initial deposit and account commitment acts as the source and second proof target is new state of deposit and account commitment
      new RollupStateTransition(p1.publicInput.source, p2.publicInput.target)
    );
  }
}
