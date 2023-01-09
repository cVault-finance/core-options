// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import "./CoreBaseVault.sol";

contract CoreLongVault is CoreBaseVault {
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
            "Core Vault Long Option Ownership",
            "CVLOO"
        )
    {}

    function deposit(address token, uint256 size) external payable override nonReentrant {
        if (token == address(0)) {
            uint256 remaining = msg.value - size;
            if (remaining > 0) payable(msg.sender).transfer(remaining);
        } else {
            payable(msg.sender).transfer(msg.value);
            IERC20(token).safeTransferFrom(msg.sender, address(this), size);
        }
        uint256 deltaAmount = oracleManager.getAmountOut(token, delta, size);
        IERC20(delta).safeTransferFrom(msg.sender, address(this), deltaAmount);

        uint256 id = lastOptionId++;
        options[id] = Option(msg.sender, token, size, deltaAmount, 0, 0);
        optionIndexes[msg.sender].add(id);
        emit OptionCreated(id, msg.sender, size);
    }

    function buy(uint256 id, uint256 percentage) external payable override nonReentrant {
        Option memory option = options[id];
        require(
            (option.paidPercentage + percentage).isLessThanAndEqualToDenominator(),
            "CoreVault: PERCENTAGE_OVERFLOW"
        );

        uint256 buyAmount = oracleManager
            .getAmountOut(option.token, dai, option.size * 2)
            .decimalMul(premiumFee)
            .decimalMul(percentage);
        IERC20(dai).safeTransferFrom(msg.sender, address(this), buyAmount);

        uint256 tokenId = lastTokenId++;
        _safeMint(msg.sender, tokenId);
        optionOwners[tokenId] = OptionOwner(id, percentage, buyAmount, block.timestamp + PERIOD);
        emit OptionBought(id, msg.sender, tokenId);
    }

    function execute(uint256 tokenId) external override nonReentrant {
        getApproved(tokenId); // check for NFT existence

        OptionOwner memory owner = optionOwners[tokenId];
        Option memory option = options[owner.optionId];

        if (owner.expireAt > block.timestamp)
            require(ownerOf(tokenId) == msg.sender, "CoreVault: NOT_OWNER");
        else require(msg.sender == option.writer, "CoreVault: NOT_WRITER");

        IERC20(delta).approve(address(mockSwap), option.deltaAmount.decimalMul(owner.percentage));
        uint256 tokenAmount = (option.size + mockSwap.swap(delta, option.token, option.deltaAmount))
            .decimalMul(owner.percentage);
        uint256 daiAmount = owner.buyAmount;
        if (option.token == address(0))
            daiAmount += mockSwap.swap{value: tokenAmount}(option.token, dai, tokenAmount);
        else {
            IERC20(option.token).approve(address(mockSwap), tokenAmount);
            daiAmount += mockSwap.swap(option.token, dai, tokenAmount);
        }
        if (owner.expireAt > block.timestamp) {
            uint256 repayAmount = owner.buyAmount.decimalDiv(premiumFee);
            uint256 repayWithPremium = Math.min(daiAmount, repayAmount + owner.buyAmount);

            IERC20(dai).safeTransfer(option.writer, repayWithPremium);
            IERC20(dai).safeTransfer(ownerOf(tokenId), daiAmount - repayWithPremium);
        } else {
            IERC20(dai).safeTransfer(ownerOf(tokenId), owner.buyAmount);
            IERC20(dai).safeTransfer(option.writer, daiAmount - owner.buyAmount);
        }
        _burn(tokenId);
        optionIndexes[option.writer].remove(owner.optionId);
        delete options[owner.optionId];
        delete optionOwners[tokenId];
        emit OptionExecuted(tokenId, msg.sender);
    }
}
