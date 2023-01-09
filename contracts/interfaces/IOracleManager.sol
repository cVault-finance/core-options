//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOracleManager {
    function getAmountOut(
        address srcToken,
        address dstToken,
        uint256 amountIn
    ) external returns (uint256);
}
