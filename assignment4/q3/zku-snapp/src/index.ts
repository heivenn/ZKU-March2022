import {
  Field,
  SmartContract,
  state,
  State,
  method,
  UInt64,
  Mina,
  Party,
  isReady,
  PrivateKey,
} from 'snarkyjs';

export { deploy, update, getSnappState };

// ensure snarkyjs is loaded first
await isReady;

/**
 * The Sum contract initializes the state variables 'num1', 'num2' and 'sum' to be a Field(0) value by default when deployed.
 * When the 'update' method is called, the Sum contract sets 'num1' and 'num2' to the parameters and updates the 'sum' field
 * to equal the sum of the two numbers, num1.add(num2).
 */
class Sum extends SmartContract {
  @state(Field) num1 = State<Field>();
  @state(Field) num2 = State<Field>();
  @state(Field) sum = State<Field>();

  // initialize balance of snapp account, uninitialized values are set to zero by default
  deploy(initialBalance: UInt64) {
    super.deploy();
    this.balance.addInPlace(initialBalance);
  }

  // takes two numbers, sets the fields as them, and the sum field as the sum of the two numbers
  @method async update(num1: Field, num2: Field) {
    this.num1.set(num1);
    this.num2.set(num2);
    const newStateSum = num1.add(num2);
    newStateSum.assertEquals(num1.add(num2));
    this.sum.set(newStateSum);
  }
}

// setup
const Local = Mina.LocalBlockchain();
Mina.setActiveInstance(Local);
const account1 = Local.testAccounts[0].privateKey;
const account2 = Local.testAccounts[1].privateKey;

const snappPrivkey = PrivateKey.random();
let snappAddress = snappPrivkey.toPublicKey();

// Deploys the snapp
async function deploy() {
  let tx = Mina.transaction(account1, async () => {
    // account2 sends 1000000000 to the new snapp account
    const initialBalance = UInt64.fromNumber(1000000);
    const p = await Party.createSigned(account2);
    p.balance.subInPlace(initialBalance);
    let snapp = new Sum(snappAddress);
    snapp.deploy(initialBalance);
  });
  await tx.send().wait();
}

// Runs the update function with the two numbers to be summed
async function update(num1: number, num2: number) {
  let tx = Mina.transaction(account2, async () => {
    let snapp = new Sum(snappAddress);
    await snapp.update(new Field(num1), new Field(num2));
  });
  try {
    await tx.send().wait();
    return true;
  } catch (err) {
    console.log(err);
    return false;
  }
}

// Retrieves all Fields from our snapp
async function getSnappState() {
  let snappState = (await Mina.getAccount(snappAddress)).snapp.appState;
  let [num1, num2, sum] = snappState;
  return { num1, num2, sum };
}
