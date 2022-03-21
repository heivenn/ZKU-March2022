pragma circom 2.0.3;

/*
    Prove: I know (x1,y1,x2,y2,x3,y3,energy) such that:
    - (x2-x1)^2 + (y2-y1)^2 <= energy^2
    - (x3-x2)^2 + (y3-y2)^2 <= energy^2
    - (x1*(y2-y3) + x2*(y3-y1) + x3*(y1-y2)) != 0
*/
template Jump () {
    signal input x1; // coordinates of a
    signal input y1;
    signal input x2; // coordinates of b
    signal input y2;
    signal input x3; // coordinates of c
    signal input y3;
    signal input energy;
    signal output out;

    // distanceSq = diffX2X1Sq + diffY2Y1Sq
    // verify that A to B move distance is within energy bounds
    signal diffX2X1;
    signal diffY2Y1;
    signal diffX2X1Sq;
    signal diffY2Y1Sq;
    signal distanceAToBSq;
    signal energySq;
    energySq <== energy * energy;
    diffX2X1 <== x2 - x1;
    diffY2Y1 <== y2 - y1;
    diffX2X1Sq <== diffX2X1 * diffX2X1;
    diffY2Y1Sq <== diffY2Y1 * diffY2Y1;
    distanceAToBSq <== diffX2X1Sq + diffY2Y1Sq;
    assert(energySq >= distanceAToBSq);

    // verify that B to C move distance is within energy bounds
    // we assume energy is replenished so we use the same energy square
    signal diffX3X2;
    signal diffY3Y2;
    signal diffX3X2Sq;
    signal diffY3Y2Sq;
    signal distanceBtoCSq;
    diffX3X2 <== x3 - x2;
    diffY3Y2 <== y3 - y2;
    diffX3X2Sq <== diffX3X2 * diffX3X2;
    diffY3Y2Sq <== diffY3Y2 * diffY3Y2;
    distanceBtoCSq <== diffX3X2Sq + diffY3Y2Sq;
    assert(energySq >= distanceBtoCSq);


    // verify that all three coordinates do not lie on a line, area of triangle must not equal 0
    // area of triangle = (1/2) * (x1(y2-y3)+ x2(y3-y1) + x3(y1-y2))
    // we want to avoid division, and since we only want area != 0 and 0/2 is still 0, we omit multiplying by (1/2) in the formula
    signal diffY2Y3;
    signal diffY3Y1;
    signal diffY1Y2;
    diffY2Y3 <== y2 - y3;
    diffY3Y1 <== y3 - y1;
    diffY1Y2 <== y1 - y2;
    signal firstAreaCalc;
    signal secondAreaCalc;
    signal firstAndSecondAreaCalc;
    signal thirdAreaCalc;
    signal area;
    firstAreaCalc <== x1 * diffY2Y3;
    secondAreaCalc <== x2 * diffY3Y1;
    thirdAreaCalc <== x3 * diffY1Y2;
    firstAndSecondAreaCalc <== firstAreaCalc + secondAreaCalc;
    area <== firstAndSecondAreaCalc + thirdAreaCalc;
    assert(area != 0);

    out <== 1;
}


component main = Jump();
