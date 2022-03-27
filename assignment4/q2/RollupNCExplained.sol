/*
 *   Q2.1.1 Updates state with new merkle root by providing proof that updatestate circuit was
 *   done correctly and used previous merkle root as input
 */
function updateState(
    uint256[2] memory a,
    uint256[2][2] memory b,
    uint256[2] memory c,
    uint256[3] memory input // 1. new balance tree merkle root,  2. merkle root of transactions tree, and 3. old balance tree merkle root
) public onlyCoordinator {
    // compare merkle root of old balance tree with snark input
    require(currentRoot == input[2], "input does not match current root");
    // validate proof that new balance tree root was computed correctly
    require(update_verifyProof(a, b, c, input), "SNARK proof is invalid");
    // update merkle root with new balance tree root
    currentRoot = input[0];
    // increase number of updates to the balance tree that have been made so far
    updateNumber++;
    // associate transaction tree root with the update number
    updates[input[1]] = updateNumber;
    // broadcast new balance root, transaction root and old balance root publicly
    emit UpdatedState(input[0], input[1], input[2]); //newRoot, txRoot, oldRoot
}

/*
 *  Q2.1.2 Creates a deposit of ERC20 token in pendingDeposits and hashes it into a subtree root hash
 *  if a perfect subtree is completed, to be processed by the operator later.
 */
function deposit(
    uint256[2] memory pubkey,
    uint256 amount,
    uint256 tokenType
) public payable {
    // only token types 1 (ETH) or other ERC20 have value
    if (tokenType == 0) {
        require(
            msg.sender == coordinator,
            "tokenType 0 is reserved for coordinator"
        );
        require(
            amount == 0 && msg.value == 0,
            "tokenType 0 does not have real value"
        );
    } else if (tokenType == 1) {
        require(
            msg.value > 0 && msg.value >= amount,
            "msg.value must at least equal stated amount in wei"
        );
    } else if (tokenType > 1) {
        require(amount > 0, "token deposit must be greater than 0");
        address tokenContractAddress = tokenRegistry.registeredTokens(
            tokenType
        );
        tokenContract = IERC20(tokenContractAddress);
        require(
            tokenContract.transferFrom(msg.sender, address(this), amount),
            "token transfer not approved"
        );
    }

    // used to create deposit hash of following values
    uint256[] memory depositArray = new uint256[](5);
    // eddsa public keys
    depositArray[0] = pubkey[0];
    depositArray[1] = pubkey[1];
    // transaction amount
    depositArray[2] = amount;
    // nonce
    depositArray[3] = 0;
    depositArray[4] = tokenType;
    // hashes values together with mimc hash function
    uint256 depositHash = mimcMerkle.hashMiMC(depositArray);
    pendingDeposits.push(depositHash);
    // notifies operator that a deposit has been made
    emit RequestDeposit(pubkey, amount, tokenType);
    queueNumber++;
    uint256 tmpDepositSubtreeHeight = 0;
    uint256 tmp = queueNumber;
    // if your deposit leaf makes a perfect subtree, hash your deposit with previous deposit
    // operator will only add a perfect subtree root hash when running processDeposits
    // number of hashes done = deposit queue number / 2
    while (tmp % 2 == 0) {
        uint256[] memory array = new uint256[](2);
        array[0] = pendingDeposits[pendingDeposits.length - 2];
        array[1] = pendingDeposits[pendingDeposits.length - 1];
        // subtree root hash created
        pendingDeposits[pendingDeposits.length - 2] = mimcMerkle.hashMiMC(
            array
        );
        removeDeposit(pendingDeposits.length - 1);
        tmp = tmp / 2;
        // increase deposit subtree height
        tmpDepositSubtreeHeight++;
    }
    // tallest subtree becomes the tree height
    if (tmpDepositSubtreeHeight > depositSubtreeHeight) {
        depositSubtreeHeight = tmpDepositSubtreeHeight;
    }
}

/*
 *  Q2.1.3 Completes a withdrawal of tokens by checking for existence of the withdrawal transaction
 *  in the transaction tree, verifying their signature, and transfering the tokens to the specified address
 */
function withdraw(
    uint256[9] memory txInfo, //[pubkeyX, pubkeyY, index, toX ,toY, nonce, amount, token_type_from, txRoot]
    uint256[] memory position,
    uint256[] memory proof,
    address payable recipient,
    uint256[2] memory a,
    uint256[2][2] memory b,
    uint256[2] memory c
) public {
    // checks that token type is valid, type 0 is for coordinator only
    require(txInfo[7] > 0, "invalid tokenType");
    // tx root should be in updates as we associate it with an update number in updateState function
    require(updates[txInfo[8]] > 0, "txRoot does not exist");
    uint256[] memory txArray = new uint256[](8);
    // creates tx array without txRoot
    for (uint256 i = 0; i < 8; i++) {
        txArray[i] = txInfo[i];
    }
    uint256 txLeaf = mimcMerkle.hashMiMC(txArray);
    // checks if tx leaf is in transaction tree using merkle proof
    require(
        txInfo[8] == mimcMerkle.getRootFromProof(txLeaf, position, proof),
        "transaction does not exist in specified transactions root"
    );

    // message is hash of nonce and recipient address
    uint256[] memory msgArray = new uint256[](2);
    msgArray[0] = txInfo[5];
    msgArray[1] = uint256(recipient);

    // verifies that the eddsa signature pubkeys are valid
    require(
        withdraw_verifyProof(
            a,
            b,
            c,
            [txInfo[0], txInfo[1], mimcMerkle.hashMiMC(msgArray)]
        ),
        "eddsa signature is not valid"
    );

    // checks token type for type of withdrawal - ETH or ERC20 (needs to find token contract)
    // transfer token on tokenContract
    if (txInfo[7] == 1) {
        // ETH
        recipient.transfer(txInfo[6]);
    } else {
        // ERC20
        address tokenContractAddress = tokenRegistry.registeredTokens(
            txInfo[7]
        );
        tokenContract = IERC20(tokenContractAddress);
        require(
            tokenContract.transfer(recipient, txInfo[6]),
            "transfer failed"
        );
    }
    // broadcasts full transaction info and receiver publicly
    emit Withdraw(txInfo, recipient);
}
