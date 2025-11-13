// SPDX-License-Identifier: MIT
// run via `forge test -vvv --match-path "contracts/uniswap-v2-oracle/test/UniswapV2OracleFork.t.sol"`
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UniswapV2Oracle} from "../UniswapV2Oracle.sol";
import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router01 as IUniswapV2Router} from "../interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "../interfaces/IUniswapV2Factory.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {ExampleERC20 as ERC20} from "../mocks/ExampleERC20.sol";

contract UniswapV2OracleForkTest is Test {
    address owner = address(this);

    // Network fork configuration
    uint256 constant beamForkBlock = 6139707;
    string constant beamForkRpc = "https://subnets.avax.network/beam/mainnet/rpc";
    address constant UNISWAP_ROUTER = 0x965B104e250648d01d4B3b72BaC751Cde809D29E; // UniswapV2Router address
    address constant USDC = 0x76BF5E7d2Bcb06b1444C0a2742780051D8D0E304; // USDC token address
    // - Real holder addresses on the forked network
    address constant user1 = address(0x191C3a109770100b439124c35990103584a62f1d); // holds 30k USDC

    // Test contracts
    IUniswapV2Router router = IUniswapV2Router(UNISWAP_ROUTER);
    ERC20 usdc = ERC20(USDC);
    IUniswapV2Factory factory;
    UniswapV2Oracle oracle;
    IWETH weth;
    ERC20 tokenA;
    ERC20 tokenB;

    IUniswapV2Pair poolAW;
    IUniswapV2Pair poolBW;
    uint256 lpBalanceAW;
    uint256 lpBalanceBW;

    // Constants
    uint256 constant MINT_AMOUNT = 1000 ether;
    uint256 constant POOL_AMOUNT_A_AB = 100 ether;
    uint256 constant POOL_AMOUNT_B_AB = 50 ether;
    uint256 constant POOL_AMOUNT_A_AW = 100 ether;
    uint256 constant POOL_AMOUNT_WETH_AW = 100 ether;
    uint256 constant POOL_AMOUNT_B_BW = 20 ether;
    uint256 constant POOL_AMOUNT_WETH_BW = 10 ether;

    function setUp() public {
        // Fork Beam mainnet
        vm.createSelectFork(beamForkRpc, beamForkBlock);

        // Give wallets native coins
        vm.deal(owner, POOL_AMOUNT_WETH_AW + POOL_AMOUNT_WETH_BW + 1e6 ether);
        vm.deal(user1, 1e6 ether);

        // Deploy the Oracle contract using ERC1967Proxy
        UniswapV2Oracle impl = new UniswapV2Oracle();
        bytes memory initData = abi.encodeWithSelector(
            UniswapV2Oracle.initialize.selector, UNISWAP_ROUTER, USDC, owner
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        oracle = UniswapV2Oracle(address(proxy));

        // - store related contracts
        address weth_ = router.WETH();
        weth = IWETH(weth_);
        address factory_ = router.factory();
        factory = IUniswapV2Factory(factory_);

        // Deploy tokens
        tokenA = new ERC20();
        tokenB = new ERC20();

        // - Mint tokens to wallets
        tokenA.mint(user1, MINT_AMOUNT);
        tokenB.mint(user1, MINT_AMOUNT);
        // -- "owner" auto-mints 1e28 when deploying

        // - Get WETH
        weth.deposit{value: POOL_AMOUNT_WETH_AW + POOL_AMOUNT_WETH_BW}();

        vm.prank(user1);
        weth.deposit{value: 1e5}();

        // Approve the router contract to spend tokens for each wallet
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        ERC20(address(weth)).approve(address(router), type(uint256).max);

        vm.startPrank(user1);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        ERC20(address(weth)).approve(address(router), type(uint256).max);
        vm.stopPrank();

        // Create LPs for tokens
        // - A & WETH
        router.addLiquidity(
            address(tokenA),
            address(weth),
            POOL_AMOUNT_A_AW,
            POOL_AMOUNT_WETH_AW,
            POOL_AMOUNT_A_AW,
            POOL_AMOUNT_WETH_AW,
            owner,
            block.timestamp + 100
        );
        address aw_ = factory.getPair(address(tokenA), address(weth));
        poolAW = IUniswapV2Pair(aw_);
        lpBalanceAW = poolAW.balanceOf(owner);

        // - B & WETH
        router.addLiquidity(
            address(tokenB),
            address(weth),
            POOL_AMOUNT_B_BW,
            POOL_AMOUNT_WETH_BW,
            POOL_AMOUNT_B_BW,
            POOL_AMOUNT_WETH_BW,
            owner,
            block.timestamp + 100
        );
        address bw_ = factory.getPair(address(tokenB), address(weth));
        poolBW = IUniswapV2Pair(bw_);
        lpBalanceBW = poolBW.balanceOf(owner);
    }

    /**
     * TESTS
     */
    function _testPredict(
        address fromToken,
        address toToken,
        uint256 fromTokenAmount,
        uint256 predictedToAmount
    ) internal {
        vm.startPrank(user1);

        uint256 balanceBefore = ERC20(toToken).balanceOf(user1);

        // trade "tokenFromAmount"
        router.swapExactTokensForTokens(
            fromTokenAmount, // exact input amount
            predictedToAmount * 99 / 100, // minimum output amount
            oracle.getUniswapV2Path(fromToken, toToken),
            user1,
            block.timestamp + 100
        );
        uint256 balanceAfter = ERC20(toToken).balanceOf(user1);
        uint256 balanceGained = balanceAfter - balanceBefore;

        assertEq(predictedToAmount, balanceGained);

        vm.stopPrank();
    }

    function testFuzz_PredictA2USDC(
        uint256 tokenAmount
    ) public {
        address fromToken = address(tokenA);
        address toToken = address(usdc);
        tokenAmount = bound(tokenAmount, 1 ether, 10 ether);
        uint256 predictedAmount = oracle.tokenToUSDC(fromToken, tokenAmount);

        _testPredict(fromToken, toToken, tokenAmount, predictedAmount);
    }

    function testFuzz_PredictUSDC2A(
        uint256 usdcAmount
    ) public {
        address fromToken = address(usdc);
        address toToken = address(tokenA);
        usdcAmount = bound(usdcAmount, 1e6, 100e6);
        uint256 predictedAmount = oracle.usdcToToken(toToken, usdcAmount);

        _testPredict(fromToken, toToken, usdcAmount, predictedAmount);
    }

    function testFuzz_PredictA2B(
        uint256 tokenAmount
    ) public {
        address fromToken = address(tokenA);
        address toToken = address(tokenB);
        tokenAmount = bound(tokenAmount, 1 ether, MINT_AMOUNT / 2);
        uint256 predictedAmount = oracle.tokenToToken(fromToken, toToken, tokenAmount);

        _testPredict(fromToken, toToken, tokenAmount, predictedAmount);
    }

    function testFuzz_PredictB2A(
        uint256 tokenAmount
    ) public {
        address fromToken = address(tokenB);
        address toToken = address(tokenA);
        tokenAmount = bound(tokenAmount, 1 ether, MINT_AMOUNT / 2);
        uint256 predictedAmount = oracle.tokenToToken(fromToken, toToken, tokenAmount);

        _testPredict(fromToken, toToken, tokenAmount, predictedAmount);
    }

    function test_GetTokenPrice_EmptyArray() public view {
        address[] memory tokens = new address[](0);
        UniswapV2Oracle.TokenPrice[] memory prices = oracle.getTokenPrice(tokens);
        assertEq(prices.length, 0);
    }

    function test_GetTokenPriceSingleToken() public view {
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenA);
        UniswapV2Oracle.TokenPrice[] memory prices = oracle.getTokenPrice(tokens);
        assertEq(prices.length, 1);
        assertEq(prices[0].token, address(tokenA));
        assertEq(prices[0].name, "Mock Token");
        assertEq(prices[0].symbol, "MOCK");
        assertEq(prices[0].decimals, 18);
        assertGt(prices[0].usdcPrice, 0);
    }

    function test_GetTokenPriceMultipleTokens() public view {
        address[] memory tokens = new address[](3);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        tokens[2] = address(usdc);
        UniswapV2Oracle.TokenPrice[] memory prices = oracle.getTokenPrice(tokens);
        assertEq(prices.length, 3);
        assertEq(prices[0].token, address(tokenA));
        assertEq(prices[1].token, address(tokenB));
        assertEq(prices[2].token, address(usdc));
        assertEq(prices[2].usdcPrice, 1e6); // USDC price in USDC should be 1e6
    }

    // TODO: add test for LP tokens (from AND to)
    function test_GetTokenPriceLPToken() public view {
        address[] memory tokens = new address[](1);
        tokens[0] = address(poolAW);
        UniswapV2Oracle.TokenPrice[] memory prices = oracle.getTokenPrice(tokens);
        assertEq(prices.length, 1);
        assertEq(prices[0].token, address(poolAW));
        assertEq(prices[0].name, "Uniswap V2 WMC/MOCK");
        assertEq(prices[0].symbol, "LP-WMC/MOCK");
        assertEq(prices[0].decimals, 18);
        assertGt(prices[0].usdcPrice, 0);
    }

    function test_GetTokenPriceWithAmounts() public view {
        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2 ether;
        amounts[1] = 3 ether;
        UniswapV2Oracle.TokenPrice[] memory prices = oracle.getTokenPrice(tokens, amounts);
        assertEq(prices.length, 2);
        assertEq(prices[0].tokenAmount, 2 ether);
        assertEq(prices[1].tokenAmount, 3 ether);
        assertGt(prices[0].usdcValue, 0);
        assertGt(prices[1].usdcValue, 0);
    }

    function test_GetTokenPriceWithAmountsZeroAmounts() public view {
        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 0;
        UniswapV2Oracle.TokenPrice[] memory prices = oracle.getTokenPrice(tokens, amounts);
        assertEq(prices.length, 2);
        assertEq(prices[0].tokenAmount, 0);
        assertEq(prices[1].tokenAmount, 0);
        assertEq(prices[0].usdcValue, 0);
        assertEq(prices[1].usdcValue, 0);
    }

    function test_GetTokenPriceWithAmountsLPToken() public view {
        address[] memory tokens = new address[](1);
        tokens[0] = address(poolAW);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;
        UniswapV2Oracle.TokenPrice[] memory prices = oracle.getTokenPrice(tokens, amounts);
        assertEq(prices.length, 1);
        assertEq(prices[0].token, address(poolAW));
        assertEq(prices[0].tokenAmount, 1e18);
        assertGt(prices[0].usdcValue, 0);
    }

    function test_GetTokenPriceWithAmountsMismatchedArrays() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        uint256[] memory amounts = new uint256[](1);
        vm.expectRevert(UniswapV2Oracle.InvalidInput.selector);
        oracle.getTokenPrice(tokens, amounts);
    }

    function test_GetTokenPriceWithOwner() public view {
        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        UniswapV2Oracle.TokenPrice[] memory prices = oracle.getTokenPrice(tokens, user1);
        assertEq(prices.length, 2);
        assertEq(prices[0].token, address(tokenA));
        assertEq(prices[1].token, address(tokenB));
        assertEq(prices[0].tokenAmount, tokenA.balanceOf(user1));
        assertEq(prices[1].tokenAmount, tokenB.balanceOf(user1));
        assertGt(prices[0].usdcValue, 0);
        assertGt(prices[1].usdcValue, 0);
    }

    function test_GetTokenPriceWithOwnerZeroBalance() public view {
        address[] memory tokens = new address[](1);
        tokens[0] = address(poolAW);
        UniswapV2Oracle.TokenPrice[] memory prices =
            oracle.getTokenPrice(tokens, address(0xdeadbeef));
        assertEq(prices.length, 1);
        assertEq(prices[0].tokenAmount, 0);
        assertEq(prices[0].usdcValue, 0);
    }

    function test_GetTokenPriceNonERC20() public view {
        address[] memory tokens = new address[](1);
        tokens[0] = address(0xdeadbeef);
        UniswapV2Oracle.TokenPrice[] memory prices = oracle.getTokenPrice(tokens);
        assertEq(prices.length, 1);
        assertEq(prices[0].name, "N/A");
        assertEq(prices[0].symbol, "N/A");
        assertEq(prices[0].decimals, 0);
        assertEq(prices[0].usdcPrice, 0);
    }

    function test_GetTokenMetadataMock() public view {
        (string memory name, string memory symbol, uint8 decimals) =
            oracle.getTokenMetadata(address(tokenA));
        assertEq(name, "Mock Token");
        assertEq(symbol, "MOCK");
        assertEq(decimals, 18);
    }

    function test_GetTokenMetadataUsdc() public view {
        (string memory name, string memory symbol, uint8 decimals) =
            oracle.getTokenMetadata(address(usdc));
        assertEq(name, "USD Coin");
        assertEq(symbol, "USDC");
        assertEq(decimals, 6);
    }

    function test_GetTokenMetadataWeth() public view {
        (string memory name, string memory symbol, uint8 decimals) =
            oracle.getTokenMetadata(address(weth));
        assertEq(name, "Wrapped Merit Circle");
        assertEq(symbol, "WMC");
        assertEq(decimals, 18);
    }

    function test_GetTokenMetadataNonERC20() public view {
        (string memory name, string memory symbol, uint8 decimals) =
            oracle.getTokenMetadata(address(0xdeadbeef));
        assertEq(name, "N/A");
        assertEq(symbol, "N/A");
        assertEq(decimals, 0);
    }

    function test_GetTokenMetadataLP() public view {
        (string memory name, string memory symbol, uint8 decimals) =
            oracle.getTokenMetadata(address(poolBW));
        assertEq(name, "Uniswap V2 MOCK/WMC");
        assertEq(symbol, "LP-MOCK/WMC");
        assertEq(decimals, 18);
    }

    function test_IsLPToken() public view {
        bool isLp = address(poolAW) != address(0) && oracle.isLPToken(address(poolAW));
        assertTrue(isLp);
        bool notLp = oracle.isLPToken(address(tokenA));
        assertFalse(notLp);
    }

    function test_ResolveLPTokenA() public view {
        (address t0, uint256 a0, address t1, uint256 a1) =
            oracle.resolveLPToken(address(poolAW), lpBalanceAW);
        assertEq(t0, poolAW.token0());
        assertEq(t1, poolAW.token1());
        assertEq(address(weth), t0);
        assertEq(POOL_AMOUNT_WETH_AW, a0);
        assertEq(POOL_AMOUNT_A_AW, a1);
    }

    function test_ResolveLPTokenB() public view {
        (address t0, uint256 a0, address t1, uint256 a1) =
            oracle.resolveLPToken(address(poolBW), lpBalanceBW);
        assertEq(t0, poolBW.token0());
        assertEq(t1, poolBW.token1());
        assertEq(address(weth), t1);
        assertEq(POOL_AMOUNT_WETH_BW, a1);
        assertEq(POOL_AMOUNT_B_BW, a0);
    }

    /* BASIC TESTS */

    function test_GetTokenPriceMismatchedArrayReverts() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        uint256[] memory amounts = new uint256[](1);
        vm.expectRevert(UniswapV2Oracle.InvalidInput.selector);
        oracle.getTokenPrice(tokens, amounts);
    }

    function test_GetTokenPriceBaseSingleToken() public view {
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenA);
        UniswapV2Oracle.TokenPrice[] memory prices = oracle.getTokenPrice(tokens);
        assertEq(prices.length, 1);
        assertEq(prices[0].token, address(tokenA));
    }

    function test_GetTokenPriceBaseMultipleTokens() public view {
        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        UniswapV2Oracle.TokenPrice[] memory prices = oracle.getTokenPrice(tokens);
        assertEq(prices.length, 2);
        assertEq(prices[1].token, address(tokenB));
    }

    function test_GetTokenPriceBaseWithAmounts() public view {
        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        UniswapV2Oracle.TokenPrice[] memory prices = oracle.getTokenPrice(tokens, amounts);
        assertEq(prices[0].tokenAmount, 1 ether);
        assertEq(prices[1].tokenAmount, 2 ether);
    }

    function test_GetTokenPriceBaseWithOwner() public view {
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenA);
        UniswapV2Oracle.TokenPrice[] memory prices = oracle.getTokenPrice(tokens, user1);
        assertEq(prices[0].token, address(tokenA));
        assertEq(prices[0].tokenAmount, tokenA.balanceOf(user1));
    }

    function test_TokenToUSDCZeroAmount() public view {
        uint256 result = oracle.tokenToUSDC(address(tokenA), 0);
        assertEq(result, 0);
    }

    function test_TokenToUSDCSameToken() public view {
        uint256 result = oracle.tokenToUSDC(USDC, 1234);
        assertEq(result, 1234);
    }

    function test_UsdcToTokenZeroAmount() public view {
        uint256 result = oracle.usdcToToken(address(tokenA), 0);
        assertEq(result, 0);
    }

    function test_UsdcToTokenSameToken() public view {
        uint256 result = oracle.usdcToToken(USDC, 5678);
        assertEq(result, 5678);
    }

    function test_TokenToTokenZeroAmount() public view {
        uint256 result = oracle.tokenToToken(address(tokenA), address(tokenB), 0);
        assertEq(result, 0);
    }

    function test_TokenToTokenSameToken() public view {
        uint256 result = oracle.tokenToToken(address(tokenA), address(tokenA), 999);
        assertEq(result, 999);
    }

    function test_TokenToTokenNonexistentPairReturnsZero() public view {
        address fake = address(0xdeadbeef);
        uint256 result = oracle.tokenToToken(fake, address(tokenA), 1 ether);
        assertEq(result, 0);
    }

    function test_TokenToUSDCBaseLPToken() public view {
        uint256 lpAmount = 1e18;
        uint256 value = oracle.tokenToUSDC(address(poolAW), lpAmount);
        assertTrue(value > 0);
    }

    function test_UsdcToTokenBaseLPToken() public view {
        uint256 usdcAmount = 1e6;
        uint256 lp = oracle.usdcToToken(address(poolAW), usdcAmount);
        assertTrue(lp > 0);
    }

    function test_TokenToTokenBaseLPToken() public view {
        uint256 amount = 1e18;
        uint256 value = oracle.tokenToToken(address(poolAW), address(tokenA), amount);
        assertTrue(value > 0);
    }

    function test_OnlyOwnerCanUpgrade() public {
        bytes memory noOpSelector;

        {
            address newImpl = address(new UniswapV2Oracle());
            vm.prank(owner);
            oracle.upgradeToAndCall(newImpl, noOpSelector);
            // If no revert, upgrade succeeded
        }

        {
            address newImpl = address(new UniswapV2Oracle());
            vm.prank(address(0x1234));
            vm.expectRevert();
            oracle.upgradeToAndCall(newImpl, noOpSelector);
        }
    }
}
