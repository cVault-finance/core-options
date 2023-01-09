//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "../interfaces/IOracle.sol";
import "../libraries/FixedPoint.sol";
import "../libraries/UniswapV2OracleLibrary.sol";

contract UniV2Oracle is IOracle {
    using FixedPoint for *;

    uint256 public constant PERIOD = 24 hours;

    IUniswapV2Pair immutable pair;
    address public immutable token0;
    address public immutable token1;
    address public immutable weth;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint32 public blockTimestampLast;
    FixedPoint.uq112x112 public price0Average;
    FixedPoint.uq112x112 public price1Average;

    bool private firstUpdated = false;

    constructor(
        address factory,
        address tokenA,
        address tokenB,
        address weth_
    ) {
        IUniswapV2Pair _pair = IUniswapV2Pair(IUniswapV2Factory(factory).getPair(tokenA, tokenB));
        weth = weth_;
        pair = _pair;
        token0 = _pair.token0();
        token1 = _pair.token1();
        price0CumulativeLast = _pair.price0CumulativeLast(); // fetch the current accumulated price value (1 / 0)
        price1CumulativeLast = _pair.price1CumulativeLast(); // fetch the current accumulated price value (0 / 1)
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = _pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, "ExampleOracleSimple: NO_RESERVES"); // ensure that there's liquidity in the pair
    }

    function tokens() external view override returns (address, address) {
        return (token0 == weth ? address(0) : token0, token1 == weth ? address(0) : token1);
    }

    function update() public {
        (
            uint256 price0Cumulative,
            uint256 price1Cumulative,
            uint32 blockTimestamp
        ) = UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        if (firstUpdated && timeElapsed < PERIOD) {
            return;
        }

        firstUpdated = true;

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        price0Average = FixedPoint.uq112x112(
            uint224((price0Cumulative - price0CumulativeLast) / timeElapsed)
        );
        price1Average = FixedPoint.uq112x112(
            uint224((price1Cumulative - price1CumulativeLast) / timeElapsed)
        );

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
    }

    function getAmountOut(address token, uint256 amountIn)
        external
        override
        returns (uint256 amountOut)
    {
        update();
        if (token == token0 || (token == address(0) && token0 == weth)) {
            amountOut = price0Average.mul(amountIn).decode144();
        } else {
            require(
                token == token1 || (token == address(0) && token1 == weth),
                "ExampleOracleSimple: INVALID_TOKEN"
            );
            amountOut = price1Average.mul(amountIn).decode144();
        }
    }
}
