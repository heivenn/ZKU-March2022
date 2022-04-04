## Q3.5 Bonus

Uses [ethers-rs](https://github.com/gakonst/ethers-rs) to call 'jump' function on [Jump.sol](https://github.com/heivenn/ZKU-March2022/blob/main/assignment3/q1/Jump.sol) smart contract created in assignment 3.

To run, first you need [ganache-cli](https://github.com/trufflesuite/ganache-cli-archive/blob/master/README.md). Note, ganache is now recommended over ganache-cli, but ethers-rs [Ganache utils](https://github.com/gakonst/ethers-rs/blob/master/ethers-core/src/utils/ganache.rs) does not seem to work with the new ganache pkg on my local dev.

```console
$ npm install ganache-cli --global
```

Run main.rs in root directory

```console
$ cargo run
```
