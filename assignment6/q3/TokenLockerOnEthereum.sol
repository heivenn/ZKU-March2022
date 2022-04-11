// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

// Harmony Light Client (HLC) is a smart contract on Ethereum that keeps track of Harmony blockchain state via stored checkpoint blocks
import "./HarmonyLightClient.sol";
import "./lib/MMRVerifier.sol";
// Harmony Prover (HProver) is a Harmony full node or a client that has access to a full node
import "./HarmonyProver.sol";
import "./TokenLocker.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// validate proof-of-burn with Harmony Prover to unlock tokens on Etherum, or lock tokens in Ethereum to be minted on Harmony
contract TokenLockerOnEthereum is TokenLocker, OwnableUpgradeable {
    HarmonyLightClient public lightclient;

    // prevents double spending
    mapping(bytes32 => bool) public spentReceipt;

    function initialize() external initializer {
        __Ownable_init();
    }

    function changeLightClient(HarmonyLightClient newClient)
        external
        onlyOwner
    {
        lightclient = newClient;
    }

    function bind(address otherSide) external onlyOwner {
        otherSideBridge = otherSide;
    }

    // Proof of burn is a combination of block inclusion proof over MMR and burn transaction inclusion proof that Harmony Light Client can verify for burn transaction inclusion
    function validateAndExecuteProof(
        HarmonyParser.BlockHeader memory header,
        MMRVerifier.MMRProof memory mmrProof,
        MPT.MerkleProof memory receiptdata
    ) external {
        // checks checkpoint is valid by looking for it in the Harmony light client stored epochMmrRoots
        require(
            lightclient.isValidCheckPoint(header.epoch, mmrProof.root),
            "checkpoint validation failed"
        );
        // gets RLP-encoded block hash from BlockHeader
        bytes32 blockHash = HarmonyParser.getBlockHash(header);
        bytes32 rootHash = header.receiptsRoot;
        // gets block hash from header and checks that block hash exists in Harmony light client
        (bool status, string memory message) = HarmonyProver.verifyHeader(
            header,
            mmrProof
        );
        require(status, "block header could not be verified");
        // receiptHash = hash(blockHash, rootHash, receiptData.key)
        bytes32 receiptHash = keccak256(
            abi.encodePacked(blockHash, rootHash, receiptdata.key)
        );
        require(spentReceipt[receiptHash] == false, "double spent!");
        // verify Merkle proof that burn tx is in Ethereum tx trie
        (status, message) = HarmonyProver.verifyReceipt(header, receiptdata);
        require(status, "receipt data could not be verified");
        // mark burn tx receipt as spent to prevent double spending
        spentReceipt[receiptHash] = true;
        // executes event to unlock tokens on Ethereum that were burned on Harmony
        uint256 executedEvents = execute(receiptdata.expectedValue);
        require(executedEvents > 0, "no valid event");
    }
}
