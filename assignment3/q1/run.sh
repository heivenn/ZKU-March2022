# compile the circuit to get system of arithmetic equations representing it
# --r1cs: it generates the file multiplier2.r1cs that contains the R1CS constraint system of the circuit in binary format.
# --wasm: it generates the directory multiplier2_js that contains the Wasm code (multiplier2.wasm) and other files needed to generate the witness.
# --sym : it generates the file multiplier2.sym , a symbols file required for debugging or for printing the constraint system in an annotated mode.
# --c : it generates the directory multiplier2_cpp that contains several files (multiplier2.cpp, multiplier2.dat, and other common files for every compiled program like main.cpp, MakeFile, etc) needed to compile the C code to generate the witness.

echo "Compiling $1.circom"
circom $1.circom --r1cs --wasm --sym --c --verbose

# compute the witness with web assembly
echo "Computing the witness"
cd $1_js
node generate_witness.js $1.wasm ../input.json witness.wtns

# compute the witness with cpp
# make sure we have nlohmann-json3-dev, libgmp-dev and nasm
# cd $1_cpp
# make
# ./$1 input.json witness.wtns


# trusted setup with Groth16 zk-SNARK
# 1. Powers of tau, independent of circuit
# 2. Phase 2, dependent on circuit

echo "Generating trusted setup, phase 1"
cd ..
# start a new "powers of tau" ceremony
snarkjs powersoftau new bn128 15 pot15_0000.ptau -v

# contribute to the ceremony
snarkjs powersoftau contribute pot15_0000.ptau pot15_0001.ptau --name="First contribution" -v

echo "Phase 2 of trusted setup"
# phase 2
# generation
snarkjs powersoftau prepare phase2 pot15_0001.ptau pot15_final.ptau -v

# generate .zkey file that contains proving and verification keys along with phase 2 contributions
snarkjs groth16 setup $1.r1cs pot15_final.ptau $1_0000.zkey

# Contribute to the phase 2 of the ceremony
snarkjs zkey contribute $1_0000.zkey $1_0001.zkey --name="1st Contributor Name" -v

# export the verification key
snarkjs zkey export verificationkey $1_0001.zkey verification_key.json

# generating a proof
echo "Generating proof"
snarkjs groth16 prove $1_0001.zkey $1_js/witness.wtns proof.json public.json

echo "Verifying proof"
# verify a proof
snarkjs groth16 verify verification_key.json public.json proof.json

echo "Creating Solidity verifier"
snarkjs zkey export solidityverifier $1_0001.zkey verifier.sol

echo "Generating Solidity verifyProof parameters"
snarkjs generatecall
