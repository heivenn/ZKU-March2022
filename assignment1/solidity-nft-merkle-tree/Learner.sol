// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

contract Learners is ERC721URIStorage {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    // preallocating a tree with 8 leaves
    uint256 constant numLeaves = 8;
    bytes32[] hashes;
    bytes32 constant NULL_HASH = keccak256(abi.encodePacked(""));
    uint256 nextIndex = 0; // tracks the index for the next leaf to be added

    constructor() ERC721("Learners", "LEARN") {
        // initialize merkle tree with null values
        for (uint256 i = 0; i < numLeaves; i++) {
            hashes.push(NULL_HASH);
        }

        uint256 n = numLeaves;
        uint256 offset = 0;
        while (n > 0) {
            for (uint256 i = 0; i < n - 1; i += 2) {
                hashes.push(
                    keccak256(
                        abi.encodePacked(
                            hashes[offset + i],
                            hashes[offset + i + 1]
                        )
                    )
                );
            }
            offset += n;
            n = n / 2;
        }
    }

    function safeMint(address _to) public {
        // don't mint if the tree is full as it won't be added to the tree otherwise
        require(
            nextIndex != numLeaves,
            "Tree is full, no more leaves can be added."
        );
        uint256 tokenId = _tokenIdCounter.current();
        // create token metadata that will live on chain
        string memory tokenMetadata = tokenURI(tokenId);
        // increase token id so each token id is unique
        _tokenIdCounter.increment();
        _safeMint(_to, tokenId);
        _setTokenURI(tokenId, tokenMetadata);
        bytes32 newLeaf = keccak256(
            abi.encodePacked(msg.sender, _to, tokenId, tokenMetadata)
        );
        // update merkle tree with newLeaf
        addLeaf(newLeaf);
    }

    function addLeaf(bytes32 _leafElement) internal {
        // update the leaf with newly minted leaf data
        hashes[nextIndex] = _leafElement;
        // update the tree
        uint256 currentIndex = nextIndex;
        while (currentIndex < hashes.length - 1) {
            uint256 parentIndex = currentIndex / 2 + numLeaves;
            if (currentIndex % 2 == 0) {
                // current node is left child
                hashes[parentIndex] = keccak256(
                    abi.encodePacked(
                        hashes[currentIndex],
                        hashes[currentIndex + 1]
                    )
                );
            } else {
                // current node is right child
                hashes[parentIndex] = keccak256(
                    abi.encodePacked(
                        hashes[currentIndex - 1],
                        hashes[currentIndex]
                    )
                );
            }
            currentIndex = parentIndex;
        }
        // update leaf index
        nextIndex++;
    }

    function tokenURI(uint256 _tokenId)
        public
        pure
        override
        returns (string memory)
    {
        // encodes our metadata as json data
        bytes memory dataURI = abi.encodePacked(
            "{",
            '"name": "Learners #',
            Strings.toString(_tokenId),
            '"',
            '"description": "Learners gonna learn to earn"',
            "}"
        );

        // encodes json metadata to base64
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(dataURI)
                )
            );
    }
}
