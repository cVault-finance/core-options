//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOracle {
    function tokens() external view returns (address, address);

    function getAmountOut(address token, uint256 amount) external returns (uint256);
}
