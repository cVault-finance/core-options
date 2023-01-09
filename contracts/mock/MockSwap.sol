//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IOracleManager.sol";
import "./MockToken.sol";

contract MockSwap {
    IOracleManager public oracleManager;

    constructor(address oracleManager_) {
        oracleManager = IOracleManager(oracleManager_);
    }

    function charge() external payable {}

    function swap(
        address token0,
        address token1,
        uint256 amount0
    ) external payable returns (uint256 amount1) {
        amount1 = oracleManager.getAmountOut(token0, token1, amount0);
        if (token0 != address(0)) {
            MockToken(token0).setBalance(
                msg.sender,
                IERC20(token0).balanceOf(msg.sender) - amount0
            );
        }
        if (token1 == address(0)) {
            (bool success, ) = msg.sender.call{value: amount1}("");
            require(success, "MockSwap: TRANSFER_FAILED");
        } else {
            MockToken(token1).setBalance(
                msg.sender,
                IERC20(token1).balanceOf(msg.sender) + amount1
            );
        }
    }
}
