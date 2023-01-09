import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Contract, utils, constants, Signer } from 'ethers';
import { generateRandomAddress } from './utils';

describe('OracleManager', function () {
  const token0 = {
    address: constants.AddressZero,
  };
  let token1: Contract;
  let priceFeed: Contract;
  let chainlinkOracle: Contract;
  let oracleManager: Contract;
  let owner: Signer;
  let alice: Signer;

  beforeEach(async function () {
    [owner, alice] = await ethers.getSigners();

    const MockTokenFactory = await ethers.getContractFactory('MockToken');
    token1 = await MockTokenFactory.deploy('DELTA', 'DELTA');

    const MockChainlinkAggregatorFactory = await ethers.getContractFactory(
      'MockChainlinkAggregator',
    );
    priceFeed = await MockChainlinkAggregatorFactory.deploy(8);

    const ChainlinkOracleFactory = await ethers.getContractFactory('ChainlinkOracle');
    chainlinkOracle = await ChainlinkOracleFactory.deploy(
      token0.address,
      token1.address,
      priceFeed.address,
    );

    const OracleManagerFactory = await ethers.getContractFactory('OracleManager');
    oracleManager = await OracleManagerFactory.deploy();
  });

  describe('#registerOracle', () => {
    it('revert if msg.sender is not owner', async () => {
      await expect(
        oracleManager
          .connect(alice)
          .registerOracle(token0.address, token1.address, chainlinkOracle.address),
      ).to.revertedWith('Ownable: caller is not the owner');
    });

    it('revert if token0 and token1 are same', async () => {
      await expect(
        oracleManager
          .connect(owner)
          .registerOracle(token1.address, token1.address, chainlinkOracle.address),
      ).to.revertedWith('invalid tokens');
    });

    it('revert if token0 and token1 are not match with oracle tokens', async () => {
      await expect(
        oracleManager
          .connect(owner)
          .registerOracle(generateRandomAddress(), token1.address, chainlinkOracle.address),
      ).to.revertedWith('token and oracle not match');

      await expect(
        oracleManager
          .connect(owner)
          .registerOracle(token0.address, generateRandomAddress(), chainlinkOracle.address),
      ).to.revertedWith('token and oracle not match');

      await expect(
        oracleManager
          .connect(owner)
          .registerOracle(token1.address, generateRandomAddress(), chainlinkOracle.address),
      ).to.revertedWith('token and oracle not match');
    });

    it('should register oracle and emit OracleRegistered event', async () => {
      const tx = await oracleManager
        .connect(owner)
        .registerOracle(token0.address, token1.address, chainlinkOracle.address);
      expect(await oracleManager.oracles(token0.address, token1.address)).to.equal(
        chainlinkOracle.address,
      );
      expect(await oracleManager.oracles(token1.address, token0.address)).to.equal(
        chainlinkOracle.address,
      );

      await expect(tx)
        .to.emit(oracleManager, 'OracleRegistered')
        .withArgs(token0.address, token1.address, chainlinkOracle.address);
    });
  });

  describe('#removeOracle', () => {
    it('revert if msg.sender is not owner', async () => {
      await expect(
        oracleManager.connect(alice).removeOracle(token0.address, token1.address),
      ).to.revertedWith('Ownable: caller is not the owner');
    });

    it('revert if oracle not registered', async () => {
      await expect(
        oracleManager.connect(owner).removeOracle(token0.address, token1.address),
      ).to.revertedWith('no oracle');
    });

    it('should register oracle and emit OracleRemoved event', async () => {
      await oracleManager
        .connect(owner)
        .registerOracle(token0.address, token1.address, chainlinkOracle.address);

      const tx = await oracleManager.connect(owner).removeOracle(token0.address, token1.address);
      expect(await oracleManager.oracles(token0.address, token1.address)).to.equal(
        constants.AddressZero,
      );
      expect(await oracleManager.oracles(token1.address, token0.address)).to.equal(
        constants.AddressZero,
      );

      await expect(tx)
        .to.emit(oracleManager, 'OracleRemoved')
        .withArgs(token0.address, token1.address);
    });
  });

  describe('#registerStable', () => {
    it('revert if msg.sender is not owner', async () => {
      await expect(
        oracleManager.connect(alice).registerStable(token0.address, token1.address),
      ).to.revertedWith('Ownable: caller is not the owner');
    });

    it('revert if token0 and token1 are same', async () => {
      await expect(
        oracleManager.connect(owner).registerStable(token1.address, token1.address),
      ).to.revertedWith('invalid tokens');
    });

    it('should register stable and emit StableRegistered event', async () => {
      const tx = await oracleManager.connect(owner).registerStable(token0.address, token1.address);

      expect(await oracleManager.stables(token0.address, token1.address)).to.equal(true);
      expect(await oracleManager.stables(token1.address, token0.address)).to.equal(true);

      await expect(tx)
        .to.emit(oracleManager, 'StableRegistered')
        .withArgs(token0.address, token1.address);
    });
  });

  describe('#removeStable', () => {
    it('revert if msg.sender is not owner', async () => {
      await expect(
        oracleManager.connect(alice).removeStable(token0.address, token1.address),
      ).to.revertedWith('Ownable: caller is not the owner');
    });

    it('revert if token0 and token1 are same', async () => {
      await expect(
        oracleManager.connect(owner).removeStable(token0.address, token1.address),
      ).to.revertedWith('no stable');
    });

    it('should register stable and emit StableRemoved event', async () => {
      await oracleManager.connect(owner).registerStable(token0.address, token1.address);

      const tx = await oracleManager.connect(owner).removeStable(token0.address, token1.address);

      expect(await oracleManager.stables(token0.address, token1.address)).to.equal(false);
      expect(await oracleManager.stables(token1.address, token0.address)).to.equal(false);

      await expect(tx)
        .to.emit(oracleManager, 'StableRemoved')
        .withArgs(token0.address, token1.address);
    });
  });

  describe('#getAmountOut', () => {
    it('return same amount if they are stable', async () => {
      await oracleManager.connect(owner).registerStable(token0.address, token1.address);

      const amountIn = utils.parseEther('5');
      expect(
        await oracleManager.callStatic.getAmountOut(token1.address, token0.address, amountIn),
      ).to.equal(amountIn);

      expect(
        await oracleManager.callStatic.getAmountOut(token0.address, token1.address, amountIn),
      ).to.equal(amountIn);
    });

    it('return oracle price', async () => {
      await oracleManager
        .connect(owner)
        .registerOracle(token0.address, token1.address, chainlinkOracle.address);

      await priceFeed.setLatestRoundData(1, 1000, 0, 0, 1);

      expect(
        await oracleManager.callStatic.getAmountOut(
          token1.address,
          token0.address,
          utils.parseEther('1'),
        ),
      ).to.equal(utils.parseEther('100000'));
    });
  });
});
