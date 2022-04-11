// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import "./HarmonyParser.sol";
import "./lib/SafeCast.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
// import "openzeppelin-solidity/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
// import "openzeppelin-solidity/contracts/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

// keeps track of genesis block of Harmony and all checkpoint blocks and mmr roots
contract HarmonyLightClient is
    Initializable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    using SafeCast for *;
    using SafeMathUpgradeable for uint256;

    struct BlockHeader {
        bytes32 parentHash;
        bytes32 stateRoot;
        bytes32 transactionsRoot;
        bytes32 receiptsRoot;
        uint256 number;
        uint256 epoch;
        uint256 shard;
        uint256 time;
        bytes32 mmrRoot;
        bytes32 hash;
    }

    event CheckPoint(
        bytes32 stateRoot,
        bytes32 transactionsRoot,
        bytes32 receiptsRoot,
        uint256 number,
        uint256 epoch,
        uint256 shard,
        uint256 time,
        bytes32 mmrRoot,
        bytes32 hash
    );

    // genesis block
    BlockHeader firstBlock;
    BlockHeader lastCheckPointBlock;

    // epoch to block numbers, as there could be >=1 mmr entries per epoch
    mapping(uint256 => uint256[]) epochCheckPointBlockNumbers;

    // block number to BlockHeader
    mapping(uint256 => BlockHeader) checkPointBlocks;

    // epoch => mapping(mmrRoot => true), used to check if checkpoints are valid
    mapping(uint256 => mapping(bytes32 => bool)) epochMmrRoots;

    uint8 relayerThreshold;

    event RelayerThresholdChanged(uint256 newThreshold);
    event RelayerAdded(address relayer);
    event RelayerRemoved(address relayer);

    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE");

    modifier onlyAdmin() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "sender doesn't have admin role"
        );
        _;
    }

    modifier onlyRelayers() {
        require(
            hasRole(RELAYER_ROLE, msg.sender),
            "sender doesn't have relayer role"
        );
        _;
    }

    function adminPauseLightClient() external onlyAdmin {
        _pause();
    }

    function adminUnpauseLightClient() external onlyAdmin {
        _unpause();
    }

    function renounceAdmin(address newAdmin) external onlyAdmin {
        require(msg.sender != newAdmin, "cannot renounce self");
        grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        renounceRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function adminChangeRelayerThreshold(uint256 newThreshold)
        external
        onlyAdmin
    {
        relayerThreshold = newThreshold.toUint8();
        emit RelayerThresholdChanged(newThreshold);
    }

    function adminAddRelayer(address relayerAddress) external onlyAdmin {
        require(
            !hasRole(RELAYER_ROLE, relayerAddress),
            "addr already has relayer role!"
        );
        grantRole(RELAYER_ROLE, relayerAddress);
        emit RelayerAdded(relayerAddress);
    }

    function adminRemoveRelayer(address relayerAddress) external onlyAdmin {
        require(
            hasRole(RELAYER_ROLE, relayerAddress),
            "addr doesn't have relayer role!"
        );
        revokeRole(RELAYER_ROLE, relayerAddress);
        emit RelayerRemoved(relayerAddress);
    }

    // initialize light client
    function initialize(
        bytes memory firstRlpHeader,
        address[] memory initialRelayers,
        uint8 initialRelayerThreshold
    ) external initializer {
        HarmonyParser.BlockHeader memory header = HarmonyParser.toBlockHeader(
            firstRlpHeader
        );
        // intialize genesis block
        firstBlock.parentHash = header.parentHash;
        firstBlock.stateRoot = header.stateRoot;
        firstBlock.transactionsRoot = header.transactionsRoot;
        firstBlock.receiptsRoot = header.receiptsRoot;
        firstBlock.number = header.number;
        firstBlock.epoch = header.epoch;
        firstBlock.shard = header.shardID;
        firstBlock.time = header.timestamp;
        firstBlock.mmrRoot = HarmonyParser.toBytes32(header.mmrRoot);
        firstBlock.hash = header.hash;

        epochCheckPointBlockNumbers[header.epoch].push(header.number);
        // add genesis block to checkpoint blocks
        checkPointBlocks[header.number] = firstBlock;
        // initialize as valid epoch to mmr root
        epochMmrRoots[header.epoch][firstBlock.mmrRoot] = true;

        relayerThreshold = initialRelayerThreshold;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // grant all intial relayers the appropriate role, that will allow them to submit checkpoint blocks
        for (uint256 i; i < initialRelayers.length; i++) {
            grantRole(RELAYER_ROLE, initialRelayers[i]);
        }
    }

    // Allows relayers to submit a new checkpoint block to the Harmony light client
    function submitCheckpoint(bytes memory rlpHeader)
        external
        onlyRelayers
        whenNotPaused
    {
        HarmonyParser.BlockHeader memory header = HarmonyParser.toBlockHeader(
            rlpHeader
        );

        BlockHeader memory checkPointBlock;
        // create checkpoint block
        checkPointBlock.parentHash = header.parentHash;
        checkPointBlock.stateRoot = header.stateRoot;
        checkPointBlock.transactionsRoot = header.transactionsRoot;
        checkPointBlock.receiptsRoot = header.receiptsRoot;
        checkPointBlock.number = header.number;
        checkPointBlock.epoch = header.epoch;
        checkPointBlock.shard = header.shardID;
        checkPointBlock.time = header.timestamp;
        checkPointBlock.mmrRoot = HarmonyParser.toBytes32(header.mmrRoot);
        checkPointBlock.hash = header.hash;

        // adds it to checkpoint blocks within same epoch
        epochCheckPointBlockNumbers[header.epoch].push(header.number);
        checkPointBlocks[header.number] = checkPointBlock;
        // map checkpoint block by its epoch and mmrRoot as a valid checkpoint
        epochMmrRoots[header.epoch][checkPointBlock.mmrRoot] = true;
        emit CheckPoint(
            checkPointBlock.stateRoot,
            checkPointBlock.transactionsRoot,
            checkPointBlock.receiptsRoot,
            checkPointBlock.number,
            checkPointBlock.epoch,
            checkPointBlock.shard,
            checkPointBlock.time,
            checkPointBlock.mmrRoot,
            checkPointBlock.hash
        );
    }

    // Allows anyone to get the latest checkpoint BlockHeader nearest to the block number in the epoch
    function getLatestCheckPoint(uint256 blockNumber, uint256 epoch)
        public
        view
        returns (BlockHeader memory checkPointBlock)
    {
        require(
            epochCheckPointBlockNumbers[epoch].length > 0,
            "no checkpoints for epoch"
        );
        // gets all checkpoint block numbers within the epoch
        uint256[] memory checkPointBlockNumbers = epochCheckPointBlockNumbers[
            epoch
        ];
        uint256 nearest = 0;
        // finds the nearest checkpoint block number to the given blockNumber
        for (uint256 i = 0; i < checkPointBlockNumbers.length; i++) {
            uint256 checkPointBlockNumber = checkPointBlockNumbers[i];
            if (
                checkPointBlockNumber > blockNumber &&
                checkPointBlockNumber < nearest
            ) {
                nearest = checkPointBlockNumber;
            }
        }
        // returns the BlockHeader of checkpoint block nearest to the provided blockNumber
        checkPointBlock = checkPointBlocks[nearest];
    }

    // checks checkpoint is valid by looking for it in the tracked epochMmrRoots
    function isValidCheckPoint(uint256 epoch, bytes32 mmrRoot)
        public
        view
        returns (bool status)
    {
        return epochMmrRoots[epoch][mmrRoot];
    }
}
