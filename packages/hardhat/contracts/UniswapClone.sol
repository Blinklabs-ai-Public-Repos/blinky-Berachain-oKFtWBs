// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract UniswapClone is ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Pair {
        address token0;
        address token1;
        uint256 reserve0;
        uint256 reserve1;
    }

    mapping(bytes32 => Pair) public pairs;
    mapping(address => bool) public registeredTokens;

    event TokenRegistered(address indexed token);
    event PairCreated(address indexed token0, address indexed token1);
    event Swap(address indexed sender, uint256 amountIn, uint256 amountOut, address indexed tokenIn, address indexed tokenOut);

    constructor() {
        // Constructor left empty intentionally
    }

    function registerToken(address token) external {
        require(!registeredTokens[token], "Token already registered");
        require(IERC20(token).totalSupply() > 0, "Invalid token");

        registeredTokens[token] = true;
        emit TokenRegistered(token);
    }

    function createPair(address tokenA, address tokenB) external nonReentrant {
        require(tokenA != tokenB, "UniswapClone: IDENTICAL_ADDRESSES");
        require(registeredTokens[tokenA] && registeredTokens[tokenB], "UniswapClone: TOKEN_NOT_REGISTERED");

        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        bytes32 pairHash = keccak256(abi.encodePacked(token0, token1));
        require(pairs[pairHash].token0 == address(0), "UniswapClone: PAIR_EXISTS");

        pairs[pairHash] = Pair({
            token0: token0,
            token1: token1,
            reserve0: 0,
            reserve1: 0
        });

        emit PairCreated(token0, token1);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired
    ) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        bytes32 pairHash = keccak256(abi.encodePacked(token0, token1));
        require(pairs[pairHash].token0 != address(0), "UniswapClone: PAIR_NOT_FOUND");

        Pair storage pair = pairs[pairHash];

        if (pair.reserve0 == 0 && pair.reserve1 == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = quote(amountADesired, pair.reserve0, pair.reserve1);
            if (amountBOptimal <= amountBDesired) {
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = quote(amountBDesired, pair.reserve1, pair.reserve0);
                assert(amountAOptimal <= amountADesired);
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }

        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, address(this), amountB);

        pair.reserve0 = pair.reserve0.add(amountA);
        pair.reserve1 = pair.reserve1.add(amountB);

        return (amountA, amountB);
    }

    function swap(
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) external nonReentrant returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapClone: INSUFFICIENT_INPUT_AMOUNT");
        require(tokenIn != tokenOut, "UniswapClone: IDENTICAL_ADDRESSES");

        (address token0, address token1) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
        bytes32 pairHash = keccak256(abi.encodePacked(token0, token1));
        require(pairs[pairHash].token0 != address(0), "UniswapClone: PAIR_NOT_FOUND");

        Pair storage pair = pairs[pairHash];

        uint256 reserveIn = tokenIn == token0 ? pair.reserve0 : pair.reserve1;
        uint256 reserveOut = tokenIn == token0 ? pair.reserve1 : pair.reserve0;

        amountOut = getAmountOut(amountIn, reserveIn, reserveOut);
        require(amountOut > 0, "UniswapClone: INSUFFICIENT_OUTPUT_AMOUNT");

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        uint256 balanceIn = IERC20(tokenIn).balanceOf(address(this));
        uint256 balanceOut = IERC20(tokenOut).balanceOf(address(this));

        if (tokenIn == token0) {
            pair.reserve0 = balanceIn;
            pair.reserve1 = balanceOut;
        } else {
            pair.reserve0 = balanceOut;
            pair.reserve1 = balanceIn;
        }

        emit Swap(msg.sender, amountIn, amountOut, tokenIn, tokenOut);

        return amountOut;
    }

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        require(amountA > 0, "UniswapClone: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "UniswapClone: INSUFFICIENT_LIQUIDITY");
        amountB = amountA.mul(reserveB) / reserveA;
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "UniswapClone: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapClone: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn.mul(997);
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }
}