pragma circom 2.0.3;

include "mimcsponge.circom";

template SameSuite () {
    signal input firstCard;
    signal input secondCard;
    signal input salt;
    signal output firstCardHash;
    signal output secondCardhash;
    
    // Verify the user is not picking the same card
    assert(firstCard != secondCard);
    // Verify the user is picking a card of the same suite
    assert(firstCard % 4 == secondCard % 4);

    component hash1 = MiMCSponge(2, 220, 1);
    hash1.ins[0] <== firstCard;
    hash1.ins[1] <== salt;
    hash1.k <== 0;
    firstCardHash <== hash1.outs[0];

    component hash2 = MiMCSponge(2, 220, 1);
    hash2.ins[0] <== secondCard;
    hash2.ins[1] <== salt;
    hash2.k <== 0;
    secondCardhash <== hash2.outs[0];
}

component main = SameSuite();
