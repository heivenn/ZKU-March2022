// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
// Ethereum Light Client (ELC) is a smart contract on Harmony that keeps track of the state of the Ethereum blockchain via stored block headers
import "./EthereumLightClient.sol";
// Ethereum Prover (EProver) is an Ethereum full node or a client that has access to a full node
import "./EthereumProver.sol";
import "./TokenLocker.sol";

// validates proof-of-lock from Ethereum Prover to execute mint event of Harmony tokens or executes burn event to burn Harmony tokens to unlock tokens on Ethereum
contract TokenLockerOnHarmony is TokenLocker, OwnableUpgradeable {
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for bytes;
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    EthereumLightClient public lightclient;

    // tracks spentReceipts to prevent double spending
    mapping(bytes32 => bool) public spentReceipt;

    function initialize() external initializer {
        __Ownable_init();
    }

    function changeLightClient(EthereumLightClient newClient)
        external
        onlyOwner
    {
        lightclient = newClient;
    }

    function bind(address otherSide) external onlyOwner {
        otherSideBridge = otherSide;
    }

    // Proof of lock is a simple SPV light client proof that Ethereum Light Client can verify for lock transaction inclusion
    function validateAndExecuteProof(
        uint256 blockNo,
        bytes32 rootHash,
        bytes calldata mptkey,
        bytes calldata proof
    ) external {
        bytes32 blockHash = bytes32(lightclient.blocksByHeight(blockNo, 0));
        // verify root hash exists in an existing block hash by checking the block headers stored in the Ethereum light client
        require(
            lightclient.VerifyReceiptsHash(blockHash, rootHash),
            "wrong receipt hash"
        );
        // receiptHash = hash(blockHash, rootHash, mptKey)
        bytes32 receiptHash = keccak256(
            abi.encodePacked(blockHash, rootHash, mptkey)
        );
        // lock tx receipt should not be spent yet
        require(spentReceipt[receiptHash] == false, "double spent!");
        // verify mptKey is in MPT matching rootHash
        bytes memory rlpdata = EthereumProver.validateMPTProof(
            rootHash, // root hash of Merkle Patricia Trie
            mptkey, // key of node whose inclusion we are proving
            proof // stack of MPT nodes to be traversed during proof verification
        );
        // sets receipt hash as spent
        spentReceipt[receiptHash] = true;
        // mints tokens on Harmony that were locked on Ethereum
        uint256 executedEvents = execute(rlpdata);
        require(executedEvents > 0, "no valid event");
    }
}
