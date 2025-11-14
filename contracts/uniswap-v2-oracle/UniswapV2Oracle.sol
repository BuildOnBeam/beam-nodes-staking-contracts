// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";

contract UniswapV2Oracle is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    error ZeroAddress();
    error InvalidInput();

    struct TokenPrice {
        uint256 usdcPrice;
        uint256 usdcValue;
        uint256 tokenAmount;
        string name;
        string symbol;
        address token;
        uint8 decimals;
    }

    address public USDC;
    address public WETH;
    IUniswapV2Router02 public UNISWAP_V2_ROUTER;
    address internal UNISWAP_V2_FACTORY;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function __UniswapV2Oracle_init(
        address router,
        address usdc,
        address initialOwner
    ) internal virtual onlyInitializing {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        __UniswapV2Oracle_init_unchained(router, usdc);
    }

    function __UniswapV2Oracle_init_unchained(
        address router,
        address usdc
    ) internal virtual onlyInitializing {
        if (router == address(0) || usdc == address(0)) {
            revert ZeroAddress();
        }

        UNISWAP_V2_ROUTER = IUniswapV2Router02(router);
        UNISWAP_V2_FACTORY = UNISWAP_V2_ROUTER.factory();
        WETH = UNISWAP_V2_ROUTER.WETH();
        USDC = usdc;
    }

    function initialize(
        address router,
        address usdc,
        address initialOwner
    ) public initializer {
        __UniswapV2Oracle_init(router, usdc, initialOwner);
    }

    // Main public getters

    function getTokenPrice(
        address token
    ) public view virtual returns (TokenPrice memory) {
        return _getTokenPrice(token);
    }

    function getTokenPrices(
        address[] memory tokens
    ) public view virtual returns (TokenPrice[] memory result) {
        result = new TokenPrice[](tokens.length);
        uint256 len = tokens.length;

        for (uint256 i; i < len; ++i) {
            result[i] = _getTokenPrice(tokens[i]);
        }

        return result;
    }

    function getTokenPriceForAmount(
        address token,
        uint256 tokenAmount
    ) public view virtual returns (TokenPrice memory) {
        return _getTokenPriceForAmount(token, tokenAmount);
    }

    function getTokenPricesForAmounts(
        address[] memory tokens,
        uint256[] memory tokenAmounts
    ) public view virtual returns (TokenPrice[] memory result) {
        if (tokens.length != tokenAmounts.length) {
            revert InvalidInput();
        }

        result = new TokenPrice[](tokens.length);
        uint256 len = tokens.length;

        for (uint256 i; i < len; ++i) {
            result[i] = _getTokenPriceForAmount(tokens[i], tokenAmounts[i]);
        }

        return result;
    }

    function getTokenPriceForOwner(
        address token,
        address owner
    ) public view virtual returns (TokenPrice memory) {
        return _getTokenPriceForOwner(token, owner);
    }

    function getTokenPricesForOwner(
        address[] memory tokens,
        address owner
    ) public view virtual returns (TokenPrice[] memory result) {
        result = new TokenPrice[](tokens.length);
        uint256 len = tokens.length;

        for (uint256 i; i < len; ++i) {
            result[i] = _getTokenPriceForOwner(tokens[i], owner);
        }

        return result;
    }

    function tokenToUSDC(
        address fromToken,
        uint256 tokenAmount
    ) public view virtual returns (uint256) {
        if (tokenAmount == 0) return 0;
        if (fromToken == USDC) return tokenAmount;

        return _toTokenAmount(fromToken, USDC, tokenAmount);
    }

    function usdcToToken(
        address toToken,
        uint256 usdcAmount
    ) public view virtual returns (uint256) {
        if (usdcAmount == 0) return 0;
        if (toToken == USDC) return usdcAmount;

        return _toTokenAmount(USDC, toToken, usdcAmount);
    }

    function tokenToToken(
        address fromToken,
        address toToken,
        uint256 fromAmount
    ) public view virtual returns (uint256) {
        if (fromAmount == 0) return 0;
        if (fromToken == toToken) return fromAmount;

        return _toTokenAmount(fromToken, toToken, fromAmount);
    }

    // Public helpers

    function getTokenMetadata(
        address token
    ) public view virtual returns (string memory name, string memory symbol, uint8 decimals) {
        if (!_isContract(token)) {
            return ("N/A", "N/A", 0);
        }

        if (isLPToken(token)) {
            IUniswapV2Pair pair = IUniswapV2Pair(token);
            string memory symbol0 = IERC20Metadata(pair.token0()).symbol();
            string memory symbol1 = IERC20Metadata(pair.token1()).symbol();

            name = string(abi.encodePacked("Uniswap V2 ", symbol0, "/", symbol1));
            symbol = string(abi.encodePacked("LP-", symbol0, "/", symbol1));
            decimals = 18; // all Uniswap V2 LP tokens have 18 decimals
        } else {
            try IERC20Metadata(token).name() returns (string memory _name) {
                name = _name;
            } catch {
                name = "N/A";
            }
            try IERC20Metadata(token).symbol() returns (string memory _symbol) {
                symbol = _symbol;
            } catch {
                symbol = "N/A";
            }
            try IERC20Metadata(token).decimals() returns (uint8 _decimals) {
                decimals = _decimals;
            } catch {
                decimals = 0;
            }
        }
    }

    function isLPToken(
        address lpToken
    ) public view virtual returns (bool) {
        if (!_isContract(lpToken)) {
            return false;
        }

        try IUniswapV2Pair(lpToken).factory() returns (address factory) {
            return (factory == UNISWAP_V2_FACTORY);
        } catch {
            return false;
        }
    }

    function resolveLPToken(
        address lpToken,
        uint256 lpTokenAmount
    )
        public
        view
        virtual
        returns (address token0, uint256 amount0, address token1, uint256 amount1)
    {
        IUniswapV2Pair pair = IUniswapV2Pair(lpToken);

        token0 = pair.token0();
        token1 = pair.token1();

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 totalSupply = pair.totalSupply();
        if (totalSupply > 1000) {
            totalSupply -= 1000; // exclude minimal liquidity
        } else {
            return (token0, 0, token1, 0);
        }

        amount0 = (uint256(reserve0) * lpTokenAmount) / totalSupply;
        amount1 = (uint256(reserve1) * lpTokenAmount) / totalSupply;
    }

    /**
     * This method assumes that the tokens have an existing WETH-pair, ignoring possible direct pairs.
     * If the input tokens contain WETH, it will try swapping them directly, otherwise via WETH.
     *
     * @param fromToken fromToken
     * @param toToken toToken
     */
    function getUniswapV2Path(
        address fromToken,
        address toToken
    ) public view virtual returns (address[] memory) {
        if (fromToken == WETH || toToken == WETH) {
            address[] memory directPath = new address[](2);
            directPath[0] = fromToken;
            directPath[1] = toToken;
            return directPath;
        }

        address[] memory path = new address[](3);
        path[0] = fromToken;
        path[1] = WETH;
        path[2] = toToken;
        return path;
    }

    // Internal getters

    function _getTokenPrice(
        address token
    ) internal view virtual returns (TokenPrice memory result) {
        (result.name, result.symbol, result.decimals) = getTokenMetadata(token);
        result.usdcPrice = usdcToToken(token, 1e6);
        result.token = token;

        return result;
    }

    function _getTokenPriceForAmount(
        address token,
        uint256 tokenAmount
    ) internal view virtual returns (TokenPrice memory result) {
        result = _getTokenPrice(token);
        result.tokenAmount = tokenAmount;
        result.usdcValue = tokenToUSDC(token, tokenAmount);

        return result;
    }

    function _getTokenPriceForOwner(
        address token,
        address owner
    ) internal view virtual returns (TokenPrice memory) {
        uint256 balance = IERC20(token).balanceOf(owner);
        return _getTokenPriceForAmount(token, balance);
    }

    function _toTokenAmount(
        address fromToken,
        address toToken,
        uint256 fromAmount
    ) internal view virtual returns (uint256 toAmount) {
        toAmount = _getToTokenAmount(fromToken, toToken, fromAmount);

        if (toAmount == 0) {
            // experimental LP-token support
            if (isLPToken(fromToken)) {
                (address token0, uint256 amount0, address token1, uint256 amount1) =
                    resolveLPToken(fromToken, fromAmount);
                uint256 value0 = _getToTokenAmount(token0, toToken, amount0);
                uint256 value1 = _getToTokenAmount(token1, toToken, amount1);

                return value0 + value1;
            } else if (isLPToken(toToken)) {
                // normalize value to 1/10_000 LP, to handle low-supply LP tokens better
                (address token0, uint256 lpAmount0, address token1, uint256 lpAmount1) =
                    resolveLPToken(toToken, 1e14);

                // figure out how much "fromToken" is required to buy 1/10_000 LP token's worth of underlying tokens
                uint256 fromFor0 = _getFromTokenAmount(fromToken, token0, lpAmount0);
                uint256 fromFor1 = _getFromTokenAmount(fromToken, token1, lpAmount1);

                // normalize required "fromToken" amounts to 1 LP
                uint256 totalFromFor1LP = (fromFor0 + fromFor1) * 1e4;

                // convert the original "fromAmount" to "toAmount" based on calculated exchange rate
                if (totalFromFor1LP > 0) {
                    return (fromAmount * 1e18) / totalFromFor1LP;
                }
            }
        }

        return toAmount;
    }

    function _getToTokenAmount(
        address fromToken,
        address toToken,
        uint256 fromAmount
    ) internal view virtual returns (uint256) {
        if (!_isContract(fromToken) || !_isContract(toToken)) {
            return 0;
        }

        address[] memory path = getUniswapV2Path(fromToken, toToken);
        try UNISWAP_V2_ROUTER.getAmountsOut(fromAmount, path) returns (uint256[] memory amounts) {
            return amounts[amounts.length - 1];
        } catch {
            return 0;
        }
    }

    function _getFromTokenAmount(
        address fromToken,
        address toToken,
        uint256 toAmount
    ) internal view virtual returns (uint256) {
        if (!_isContract(fromToken) || !_isContract(toToken)) {
            return 0;
        }

        address[] memory path = getUniswapV2Path(fromToken, toToken);
        try UNISWAP_V2_ROUTER.getAmountsIn(toAmount, path) returns (uint256[] memory amounts) {
            return amounts[0];
        } catch {
            return 0;
        }
    }

    function _isContract(
        address token
    ) internal view virtual returns (bool) {
        return (token.code.length != 0);
    }

    // Internal: upgrades

    function _authorizeUpgrade(
        address /*newImplementation*/
    ) internal override onlyOwner {}
}
