//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IERC20Detailed.sol";

contract ChainlinkOracle is IOracle {
    AggregatorV3Interface public immutable priceFeed;
    address public immutable token0;
    address public immutable token1;
    uint256 public immutable decimals;
    uint256 public immutable token0Decimals;
    uint256 public immutable token1Decimals;

    constructor(
        address _token0,
        address _token1,
        address _priceFeed
    ) {
        require(_token0 != _token1, "invalid tokens");

        token0 = _token0;
        token1 = _token1;
        priceFeed = AggregatorV3Interface(_priceFeed);
        decimals = 10**AggregatorV3Interface(_priceFeed).decimals();
        token0Decimals = 10**(_token0 == address(0) ? 18 : IERC20Detailed(_token0).decimals());
        token1Decimals = 10**(_token1 == address(0) ? 18 : IERC20Detailed(_token1).decimals());
    }

    function tokens() external view override returns (address, address) {
        return (token0, token1);
    }

    function getAmountOut(address token, uint256 amount) external override returns (uint256) {
        (uint80 roundID, int256 price, , , uint80 answeredInRound) = priceFeed.latestRoundData();
        require(roundID == answeredInRound, "old price");
        require(price > 0, "invalid price");

        if (token == token0) {
            return (amount * uint256(price) * token1Decimals) / (token0Decimals * decimals);
        } else {
            require(token == token1, "invalid token");
            return (amount * token0Decimals * decimals) / (token1Decimals * uint256(price));
        }
    }
}
