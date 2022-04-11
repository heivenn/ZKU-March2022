// Harmony bridge test
// recursive length prefix, for encoding method for serializing objects in ethereum
const rlp = require('rlp');
// rlpHeader and hash of the header
const headerData = require('./headers.json');
// transaction hash and header
const transactions = require('./transaction.json');
const { rpcWrapper, getReceiptProof } = require('../scripts/utils');

const { expect } = require('chai');

// HarmonyProver receives hash of burn transaction and generates proof-of-burn when user wants to unlock their tokens on Ethereum
let MMRVerifier, HarmonyProver;
let prover, mmrVerifier;

function hexToBytes(hex) {
  for (var bytes = [], c = 0; c < hex.length; c += 2)
    bytes.push(parseInt(hex.substr(c, 2), 16));
  return bytes;
}

describe('HarmonyProver', function () {
  // test setup
  beforeEach(async function () {
    MMRVerifier = await ethers.getContractFactory('MMRVerifier');
    mmrVerifier = await MMRVerifier.deploy();
    await mmrVerifier.deployed();

    // await HarmonyProver.link('MMRVerifier', mmrVerifier);
    HarmonyProver = await ethers.getContractFactory('HarmonyProver', {
      libraries: {
        MMRVerifier: mmrVerifier.address,
      },
    });
    prover = await HarmonyProver.deploy();
    await prover.deployed();
  });

  it('parse rlp block header', async function () {
    // parse RLP-encoded block header into BlockHeader data structure
    let header = await prover.toBlockHeader(hexToBytes(headerData.rlpheader));
    expect(header.hash).to.equal(headerData.hash);
  });

  // testing if we can get proof-of-lock from EProver with tx hash and parse proof header in HProver into BlockHeader data structure and proof data
  it('parse transaction receipt proof', async function () {
    let callback = getReceiptProof;
    let callbackArgs = [process.env.LOCALNET, prover, transactions.hash];
    let isTxn = true;
    // using tx hash, we get the block header where the tx was included via rpc to interact with Ethereum client. the header is passed into the arguments of getReceiptProof as proof header data, and the rest of the proof is retrieved from EProver
    let txProof = await rpcWrapper(
      transactions.hash,
      isTxn,
      callback,
      callbackArgs
    );
    console.log(txProof);
    // check correct BlockHeader header hash
    expect(txProof.header.hash).to.equal(transactions.header);

    // let response = await prover.getBlockRlpData(txProof.header);
    // console.log(response);

    // let res = await test.bar([123, "abc", "0xD6dDd996B2d5B7DB22306654FD548bA2A58693AC"]);
    // // console.log(res);
  });
});

let TokenLockerOnEthereum, tokenLocker;
let HarmonyLightClient, lightclient;

describe('TokenLocker', function () {
  beforeEach(async function () {
    TokenLockerOnEthereum = await ethers.getContractFactory(
      'TokenLockerOnEthereum'
    );
    tokenLocker = await MMRVerifier.deploy();
    await tokenLocker.deployed();

    await tokenLocker.bind(tokenLocker.address);

    // // await HarmonyProver.link('MMRVerifier', mmrVerifier);
    // HarmonyProver = await ethers.getContractFactory(
    //     "HarmonyProver",
    //     {
    //         libraries: {
    //             MMRVerifier: mmrVerifier.address
    //         }
    //     }
    // );
    // prover = await HarmonyProver.deploy();
    // await prover.deployed();
  });

  it('issue map token test', async function () {});

  it('lock test', async function () {});

  it('unlock test', async function () {});

  it('light client upgrade test', async function () {});
});
