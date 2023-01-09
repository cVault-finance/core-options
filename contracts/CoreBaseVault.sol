// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "./interfaces/IOracleManager.sol";
import "./libraries/DecimalMath.sol";
import "./mock/MockSwap.sol";

abstract contract CoreBaseVault is Ownable, ERC721Enumerable, ReentrancyGuard {
    using DecimalMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    event OptionCreated(uint256 indexed id, address indexed writer, uint256 size);
    event OptionBought(uint256 indexed id, address indexed owner, uint256 indexed tokenId);
    event OptionExecuted(uint256 indexed id, address indexed executor);

    uint256 internal constant PERIOD = 2 weeks;

    struct Option {
        address writer;
        address token;
        uint256 size;
        uint256 deltaAmount; // DELTA token amount locked in the vault
        uint256 daiAmount; // short put only - writer's deposit amount
        uint256 paidPercentage;
    }

    struct OptionOwner {
        uint256 optionId;
        uint256 percentage; // 10000 for 100% (2 decimals allowed)
        uint256 buyAmount; // repayAmount.deimalMul(percentage)
        uint256 expireAt;
    }

    address immutable dai;
    address immutable delta;
    uint256 public premiumFee;
    MockSwap public mockSwap;
    IOracleManager public oracleManager;

    uint256 public lastOptionId;
    mapping(uint256 => Option) public options;
    mapping(address => EnumerableSet.UintSet) internal optionIndexes;

    uint256 public lastTokenId;
    mapping(uint256 => OptionOwner) public optionOwners;

    receive() external payable {}

    constructor(
        address oracleManager_,
        address dai_,
        address delta_,
        uint256 premiumFee_,
        string memory name_,
        string memory symbol_
    ) ERC721(name_, symbol_) {
        require(oracleManager_ != address(0), "CoreVault: ORACLE_MANAGER_0x0");
        require(dai_ != address(0), "CoreVault: DAI_0x0");
        require(delta_ != address(0), "CoreVault: DELTA_0x0");
        require(premiumFee_.isLessThanAndEqualToDenominator(), "CoreVault: PREMIUM_FEE_INCORRECT");

        dai = dai_;
        delta = delta_;
        premiumFee = premiumFee_;
        oracleManager = IOracleManager(oracleManager_);
    }

    function getWroteOptions(address writer) external view returns (Option[] memory) {
        EnumerableSet.UintSet storage indexes = optionIndexes[writer];
        uint256 length = indexes.length();
        Option[] memory options_ = new Option[](length);
        for (uint256 i; i < length; i += 1) options_[i] = options[indexes.at(i)];
        return options_;
    }

    function getOwnedOptions(address owner) external view returns (Option[] memory) {
        uint256 length = balanceOf(owner);
        Option[] memory options_ = new Option[](length);
        for (uint256 i; i < length; i += 1) options_[i] = options[optionOwners[i].optionId];
        return options_;
    }

    function setMockSwap(address mockSwap_) external onlyOwner {
        mockSwap = MockSwap(mockSwap_);
    }

    function setOracleManager(address oracleManager_) external onlyOwner {
        require(oracleManager_ != address(0), "CoreVault: ORACLE_MANAGER_0x0");
        oracleManager = IOracleManager(oracleManager_);
    }

    function setPremiumFee(uint256 fee) external onlyOwner {
        require(fee.isLessThanAndEqualToDenominator(), "CoreVault: PREMIUM_FEE_INCORRECT");
        premiumFee = fee;
    }

    function deposit(address token, uint256 size) external payable virtual;

    function buy(uint256 id, uint256 percentage) external payable virtual;

    function execute(uint256 tokenId) external virtual;
}
