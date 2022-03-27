import { shutdown, Field } from 'snarkyjs';
import { deploy, update, getSnappState } from './index';

describe('test sum snapp', () => {
  afterAll(async () => {
    await shutdown();
  });
  it('should deploy the contract', async () => {
    await deploy();
    let { num1, num2, sum } = await getSnappState();
    expect(num1).toEqual(Field.zero);
    expect(num2).toEqual(Field.zero);
    expect(sum).toEqual(Field.zero);
  });
  it('should update the sum correctly', async () => {
    await deploy();
    let updated = await update(1, 2);
    expect(updated).toBe(true);
    let { num1, num2, sum } = await getSnappState();
    expect(num1).toEqual(Field(1));
    expect(num2).toEqual(Field(2));
    expect(sum).toEqual(Field(3));
  });
});
