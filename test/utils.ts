import { Wallet, BigNumber } from 'ethers';
import { time } from '@openzeppelin/test-helpers';

export const DENOMINATOR = BigNumber.from('10000');

export const generateRandomAddress = () => Wallet.createRandom().address;

export const getCurrentTime = async (): Promise<BigNumber> =>
  BigNumber.from((await time.latest()).toString());

export const increaseTime = async (period: BigNumber) => {
  await time.increase(period.toString());
};
