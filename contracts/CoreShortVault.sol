// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./CoreBaseVault.sol";

contract CoreShortVault is CoreBaseVault {
    using SafeERC20 for IERC20;
    using DecimalMath for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    constructor(
        address oracleManager_,
        address dai_,
        address delta_,
        uint256 premiumFee_
    )
        CoreBaseVault(
            oracleManager_,
            dai_,
            delta_,
            premiumFee_,
            "Core Vault Short Option Ownership",
            "CVSOO"
        )
    {}

    function deposit(address token, uint256 size) external payable override nonReentrant {
        uint256 daiAmount = oracleManager.getAmountOut(token, dai, size);
        uint256 deltaAmount = oracleManager.getAmountOut(token, delta, size);
        IERC20(dai).safeTransferFrom(msg.sender, address(this), daiAmount);
        IERC20(delta).safeTransferFrom(msg.sender, address(this), deltaAmount);

        uint256 id = lastOptionId++;
        options[id] = Option(msg.sender, token, size, deltaAmount, daiAmount, 0);
        optionIndexes[msg.sender].add(id);
        emit OptionCreated(id, msg.sender, size);
    }

    function buy(uint256 id, uint256 percentage) external payable override nonReentrant {
        Option memory option = options[id];
        require(
            (option.paidPercentage + percentage).isLessThanAndEqualToDenominator(),
            "CoreVault: PERCENTAGE_OVERFLOW"
        );

        uint256 buyAmount = (option.size * 2).decimalMul(premiumFee).decimalMul(percentage);
        if (option.token == address(0)) {
            uint256 remaining = msg.value - buyAmount;
            payable(msg.sender).transfer(remaining);
        } else {
            payable(msg.sender).transfer(msg.value);
            IERC20(option.token).safeTransferFrom(msg.sender, address(this), buyAmount);
        }

        uint256 tokenId = lastTokenId++;
        _safeMint(msg.sender, tokenId);
        optionOwners[tokenId] = OptionOwner(id, percentage, buyAmount, block.timestamp + PERIOD);
        emit OptionBought(id, msg.sender, block.timestamp);
    }

    function execute(uint256 tokenId) external override nonReentrant {
        getApproved(tokenId); // check for NFT existence

        OptionOwner memory owner = optionOwners[tokenId];
        Option memory option = options[owner.optionId];

        if (owner.expireAt > block.timestamp)
            require(ownerOf(tokenId) == msg.sender, "CoreVault: NOT_OWNER");
        else require(msg.sender == option.writer, "CoreVault: NOT_WRITER");

        IERC20(dai).approve(address(mockSwap), option.daiAmount.decimalMul(owner.percentage));
        IERC20(delta).approve(address(mockSwap), option.deltaAmount.decimalMul(owner.percentage));
        uint256 tokenAmount = owner.buyAmount +
            mockSwap.swap(dai, option.token, option.daiAmount.decimalMul(owner.percentage)) +
            mockSwap.swap(delta, option.token, option.deltaAmount.decimalMul(owner.percentage));
        if (owner.expireAt > block.timestamp) {
            uint256 repayAmount = owner.buyAmount.decimalDiv(premiumFee);
            uint256 repayWithPremium = Math.min(tokenAmount, repayAmount + owner.buyAmount);

            if (option.token == address(0)) {
                payable(option.writer).transfer(repayWithPremium);
                payable(ownerOf(tokenId)).transfer(tokenAmount - repayWithPremium);
            } else {
                IERC20(option.token).safeTransfer(option.writer, repayWithPremium);
                IERC20(option.token).safeTransfer(ownerOf(tokenId), tokenAmount - repayWithPremium);
            }
        } else {
            if (option.token == address(0)) {
                payable(ownerOf(tokenId)).transfer(owner.buyAmount);
                payable(option.writer).transfer(tokenAmount - owner.buyAmount);
            } else {
                IERC20(option.token).safeTransfer(ownerOf(tokenId), owner.buyAmount);
                IERC20(option.token).safeTransfer(option.writer, tokenAmount - owner.buyAmount);
            }
        }
        _burn(tokenId);
        optionIndexes[option.writer].remove(owner.optionId);
        delete options[owner.optionId];
        delete optionOwners[tokenId];
        emit OptionExecuted(tokenId, msg.sender);
    }
}
