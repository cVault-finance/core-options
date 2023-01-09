//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IOracleManager.sol";

contract OracleManager is IOracleManager, Ownable {
    event OracleRegistered(address indexed token0, address indexed token1, address indexed oracle);
    event OracleRemoved(address indexed token0, address indexed token1);
    event StableRegistered(address indexed token0, address indexed token1);
    event StableRemoved(address indexed token0, address indexed token1);

    mapping(address => mapping(address => address)) public oracles;
    mapping(address => mapping(address => bool)) public stables;

    function registerOracle(
        address token0,
        address token1,
        address oracle
    ) external onlyOwner {
        // address(0) => ETH
        require(token0 != token1, "invalid tokens");

        (address tokenA, address tokenB) = IOracle(oracle).tokens();
        if (tokenA == token0) {
            require(tokenB == token1, "token and oracle not match");
        } else if (tokenA == token1) {
            require(tokenB == token0, "token and oracle not match");
        } else {
            revert("token and oracle not match");
        }
        oracles[token0][token1] = oracle;
        oracles[token1][token0] = oracle;

        emit OracleRegistered(token0, token1, oracle);
    }

    function removeOracle(address token0, address token1) external onlyOwner {
        require(oracles[token0][token1] != address(0), "no oracle");

        delete oracles[token0][token1];
        delete oracles[token1][token0];

        emit OracleRemoved(token0, token1);
    }

    function registerStable(address token0, address token1) external onlyOwner {
        // address(0) => ETH
        require(token0 != token1, "invalid tokens");
        stables[token0][token1] = true;
        stables[token1][token0] = true;

        emit StableRegistered(token0, token1);
    }

    function removeStable(address token0, address token1) external onlyOwner {
        require(stables[token0][token1] == true, "no stable");

        delete stables[token0][token1];
        delete stables[token1][token0];

        emit StableRemoved(token0, token1);
    }

    function getAmountOut(
        address srcToken,
        address dstToken,
        uint256 amountIn
    ) external override returns (uint256) {
        if (stables[srcToken][dstToken]) {
            return amountIn;
        }
        IOracle oracle = IOracle(oracles[srcToken][dstToken]);

        return oracle.getAmountOut(srcToken, amountIn);
    }
}
