import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Contract, BigNumber, utils } from 'ethers';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { generateRandomAddress, getCurrentTime, increaseTime } from './utils';

describe('CoreLongVault', function () {
  let owner: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let mockSwap: Contract;
  let dai: Contract;
  let delta: Contract;
  let mockToken: Contract;
  let ethDeltaPriceFeed: Contract;
  let ethDaiPriceFeed: Contract;
  let mockDeltaPriceFeed: Contract;
  let mockDaiPriceFeed: Contract;
  let oracleManager: Contract;
  let premiumFee = BigNumber.from('1000');
  let vault: Contract;
  const ZeroAddress = ethers.constants.AddressZero;

  beforeEach(async function () {
    [owner, alice, bob] = await ethers.getSigners();

    const MockSwapFactory = await ethers.getContractFactory('MockSwap');
    const MockTokenFactory = await ethers.getContractFactory('MockToken');
    const MockChainlinkAggregatorFactory = await ethers.getContractFactory(
      'MockChainlinkAggregator',
    );
    const ChainlinkOracleFactory = await ethers.getContractFactory('ChainlinkOracle');
    const OracleManagerFactory = await ethers.getContractFactory('OracleManager');
    const CoreLongVaultFactory = await ethers.getContractFactory('CoreLongVault');

    dai = await MockTokenFactory.deploy('DAI StableCoin', 'DAI');
    delta = await MockTokenFactory.deploy('Delta', 'DELTA');
    mockToken = await MockTokenFactory.deploy('Mock Token', 'MCK');
    ethDaiPriceFeed = await MockChainlinkAggregatorFactory.deploy(18);
    ethDeltaPriceFeed = await MockChainlinkAggregatorFactory.deploy(18);
    mockDaiPriceFeed = await MockChainlinkAggregatorFactory.deploy(18);
    mockDeltaPriceFeed = await MockChainlinkAggregatorFactory.deploy(18);
    const ethDaiOracle = await ChainlinkOracleFactory.deploy(
      ZeroAddress,
      dai.address,
      ethDaiPriceFeed.address,
    );
    const ethDeltaOracle = await ChainlinkOracleFactory.deploy(
      ZeroAddress,
      delta.address,
      ethDeltaPriceFeed.address,
    );
    const mockDaiOracle = await ChainlinkOracleFactory.deploy(
      mockToken.address,
      dai.address,
      mockDaiPriceFeed.address,
    );
    const mockDeltaOracle = await ChainlinkOracleFactory.deploy(
      mockToken.address,
      delta.address,
      mockDeltaPriceFeed.address,
    );
    oracleManager = await OracleManagerFactory.deploy();
    mockSwap = await MockSwapFactory.deploy(oracleManager.address);

    vault = await CoreLongVaultFactory.deploy(
      oracleManager.address,
      dai.address,
      delta.address,
      premiumFee,
    );
    await dai.setBalance(owner.address, utils.parseEther('10000'));
    await dai.setBalance(alice.address, utils.parseEther('10000'));
    await delta.setBalance(owner.address, utils.parseEther('10000'));
    await delta.setBalance(alice.address, utils.parseEther('10000'));
    await mockToken.setBalance(owner.address, utils.parseEther('10000'));
    await mockToken.setBalance(alice.address, utils.parseEther('10000'));
    await dai.approve(vault.address, utils.parseEther('10000'));
    await dai.connect(alice).approve(vault.address, utils.parseEther('10000'));
    await delta.approve(vault.address, utils.parseEther('10000'));
    await delta.connect(alice).approve(vault.address, utils.parseEther('10000'));
    await mockToken.approve(vault.address, utils.parseEther('10000'));
    await mockToken.connect(alice).approve(vault.address, utils.parseEther('10000'));
    await oracleManager.registerOracle(ZeroAddress, dai.address, ethDaiOracle.address);
    await oracleManager.registerOracle(ZeroAddress, delta.address, ethDeltaOracle.address);
    await oracleManager.registerOracle(mockToken.address, dai.address, mockDaiOracle.address);
    await oracleManager.registerOracle(mockToken.address, delta.address, mockDeltaOracle.address);
    await ethDaiPriceFeed.setLatestRoundData(1, utils.parseEther('1000'), 0, 0, 1); // 1eth = 1000 DAI
    await ethDeltaPriceFeed.setLatestRoundData(1, utils.parseEther('10'), 0, 0, 1); // 1eth = 10 DELTA
    await mockDaiPriceFeed.setLatestRoundData(1, utils.parseEther('500'), 0, 0, 1); // 1mck = 500 DAI
    await mockDeltaPriceFeed.setLatestRoundData(1, utils.parseEther('5'), 0, 0, 1); // 1mck = 5 DELTA
    await vault.setMockSwap(mockSwap.address);
  });

  describe('#setOracleManager', () => {
    const manager = generateRandomAddress();

    it('revert if msg.sender is not owner', async () => {
      await expect(vault.connect(alice).setOracleManager(manager)).to.revertedWith(
        'Ownable: caller is not the owner',
      );
    });

    it('revert if oracle manager is 0x0', async () => {
      await expect(vault.setOracleManager(ZeroAddress)).to.revertedWith(
        'CoreVault: ORACLE_MANAGER_0x0',
      );
    });

    it('should set oracle manager by owner', async () => {
      await vault.setOracleManager(manager);
      expect(await vault.oracleManager()).to.eq(manager);
    });
  });

  describe('#deposit', () => {
    it('should deposit successfully and emit OptionCreated event', async () => {
      const tx = await vault.deposit(ZeroAddress, utils.parseEther('5'), {
        value: utils.parseEther('5'),
      });
      expect(tx).emit(vault, 'OptionCreated').withArgs(0, owner.address, utils.parseEther('5'));
      expect(await ethers.provider.getBalance(vault.address)).to.eq(utils.parseEther('5'));
      expect(await delta.balanceOf(vault.address)).to.eq(utils.parseEther('50'));
    });
  });

  describe('#buy', () => {
    beforeEach(async () => {
      await vault.deposit(ZeroAddress, utils.parseEther('5'), {
        value: utils.parseEther('5'),
      });
    });

    it('should buy successfully and emit OptionBought event', async () => {
      const time = await getCurrentTime();
      const daiAliceBalance = await dai.balanceOf(alice.address);
      const tx = await vault.connect(alice).buy(0, 10000);
      expect(tx).emit(vault, 'OptionBought').withArgs(0, alice.address, time.toString());
      expect((await vault.getOwnedOptions(alice.address)).length).to.eq(1);
      expect(await dai.balanceOf(alice.address)).to.eq(
        daiAliceBalance.sub(utils.parseEther('1000')),
      );
    });
  });

  describe('#execute', () => {
    beforeEach(async () => {
      await vault.deposit(ZeroAddress, utils.parseEther('5'), { value: utils.parseEther('5') });
      await vault.connect(alice).buy(0, 10000);
    });

    it('revert if writer calls before expired', async () => {
      await expect(vault.execute(0)).to.revertedWith('CoreVault: NOT_OWNER');
    });

    it('revert if owner calls after expired', async () => {
      await increaseTime(BigNumber.from('1209700'));
      await expect(vault.connect(alice).execute(0)).to.revertedWith('CoreVault: NOT_WRITER');
    });

    it('revert if not bought yet', async () => {
      await vault.deposit(ZeroAddress, utils.parseEther('5'), { value: utils.parseEther('5') });
      await expect(vault.execute(1)).to.revertedWith(
        'ERC721: approved query for nonexistent token',
      );
    });

    it('should execute successfully and delete option', async () => {
      await mockSwap.charge({ value: utils.parseEther('10') });
      await ethDaiPriceFeed.setLatestRoundData(1, utils.parseEther('2000'), 0, 0, 1);
      await ethDeltaPriceFeed.setLatestRoundData(1, utils.parseEther('20'), 0, 0, 1);
      const daiOwnerBalance = await dai.balanceOf(owner.address);
      const daiAliceBalance = await dai.balanceOf(alice.address);
      const tx = await vault.connect(alice).execute(0);
      expect(tx).emit(vault, 'OptionExecuted').withArgs(0, alice.address);
      expect((await dai.balanceOf(owner.address)).sub(daiOwnerBalance)).to.eq(
        utils.parseEther('11000'), // repay 10000 DAI + 10%
      );
      expect((await dai.balanceOf(alice.address)).sub(daiAliceBalance)).to.eq(
        utils.parseEther('5000'), // get profit
      );
    });

    it('should execute properly after expired', async () => {
      await increaseTime(BigNumber.from('1209700'));
      await mockSwap.charge({ value: utils.parseEther('10') });
      await ethDaiPriceFeed.setLatestRoundData(1, utils.parseEther('2000'), 0, 0, 1);
      await ethDeltaPriceFeed.setLatestRoundData(1, utils.parseEther('20'), 0, 0, 1);
      const daiOwnerBalance = await dai.balanceOf(owner.address);
      const daiAliceBalance = await dai.balanceOf(alice.address);
      const tx = await vault.execute(0);
      expect(tx).emit(vault, 'OptionExecuted').withArgs(0, owner.address);
      expect((await dai.balanceOf(owner.address)).sub(daiOwnerBalance)).to.eq(
        utils.parseEther('15000'), // 5 ETH + 50 DELTA
      );
      expect((await dai.balanceOf(alice.address)).sub(daiAliceBalance)).to.eq(
        utils.parseEther('1000'), // buy amount
      );
    });

    it('transfer ownership to bob', async () => {
      await vault.connect(alice).transferFrom(alice.address, bob.address, 0);
      await mockSwap.charge({ value: utils.parseEther('10') });
      await ethDaiPriceFeed.setLatestRoundData(1, utils.parseEther('2000'), 0, 0, 1);
      await ethDeltaPriceFeed.setLatestRoundData(1, utils.parseEther('20'), 0, 0, 1);
      const daiOwnerBalance = await dai.balanceOf(owner.address);
      const daiBobBalance = await dai.balanceOf(bob.address);
      const tx = await vault.connect(bob).execute(0);
      expect(tx).emit(vault, 'OptionExecuted').withArgs(0, bob.address);
      expect((await dai.balanceOf(owner.address)).sub(daiOwnerBalance)).to.eq(
        utils.parseEther('11000'), // repay 10000 DAI + 10%
      );
      expect((await dai.balanceOf(bob.address)).sub(daiBobBalance)).to.eq(
        utils.parseEther('5000'), // get profit
      );
    });
  });

  describe.only('multi token support', () => {
    it('deposit, partial buy, execute token option', async () => {
      let tx = await vault.deposit(mockToken.address, utils.parseEther('5'));
      expect(tx).emit(vault, 'OptionCreated').withArgs(0, owner.address, utils.parseEther('5'));
      expect(await mockToken.balanceOf(vault.address)).to.eq(utils.parseEther('5'));
      expect(await delta.balanceOf(vault.address)).to.eq(utils.parseEther('25'));

      const time = await getCurrentTime();
      let daiAliceBalance = await dai.balanceOf(alice.address);
      tx = await vault.connect(alice).buy(0, 1000);
      expect(tx).emit(vault, 'OptionBought').withArgs(0, alice.address, time.toString());
      expect((await vault.getOwnedOptions(alice.address)).length).to.eq(1);
      expect(await dai.balanceOf(alice.address)).to.eq(daiAliceBalance.sub(utils.parseEther('50')));

      await mockDaiPriceFeed.setLatestRoundData(1, utils.parseEther('2000'), 0, 0, 1);
      await mockDeltaPriceFeed.setLatestRoundData(1, utils.parseEther('20'), 0, 0, 1);
      const daiOwnerBalance = await dai.balanceOf(owner.address);
      daiAliceBalance = await dai.balanceOf(alice.address);
      tx = await vault.connect(alice).execute(0);
      expect(tx).emit(vault, 'OptionExecuted').withArgs(0, alice.address);
      expect((await dai.balanceOf(owner.address)).sub(daiOwnerBalance)).to.eq(
        utils.parseEther('550'), // repay 10 mck + 10%
      );
      expect((await dai.balanceOf(alice.address)).sub(daiAliceBalance)).to.eq(
        utils.parseEther('750'), // get profit
      );
    });
  });
});
