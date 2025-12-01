// SPDX-License-Identifier: MIT
// run via `forge test -vvv --match-path "contracts/nft-redeemer/tests/NFTRedeemerTests.t.sol"`
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {NFTRedeemer} from "../NFTRedeemer.sol";

/**
 * @title MockERC721Burnable
 * @dev Minimal ERC721-like mock that supports mint, approve, ownerOf, burn, transferFrom.
 *      burn() requires msg.sender == owner || approvedForAll || getApproved == msg.sender
 *      This mock simplifies behavior but is sufficient for tests.
 */
contract MockERC721Burnable {
    string public name = "Mock";
    string public symbol = "MCK";

    mapping(uint256 => address) private _ownerOf;
    mapping(address => mapping(address => bool)) private _isApprovedForAll;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(uint256 => bool) public burned;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event Burned(address indexed operator, uint256 indexed tokenId);

    function mint(
        address to,
        uint256 tokenId
    ) external {
        require(to != address(0), "zero to");
        require(_ownerOf[tokenId] == address(0) && !burned[tokenId], "already minted");
        _ownerOf[tokenId] = to;
        emit Transfer(address(0), to, tokenId);
    }

    function ownerOf(
        uint256 tokenId
    ) public view returns (address) {
        address owner = _ownerOf[tokenId];
        require(owner != address(0), "owner query for nonexistent token");
        return owner;
    }

    function approve(
        address to,
        uint256 tokenId
    ) external {
        address owner = ownerOf(tokenId);
        require(msg.sender == owner || _isApprovedForAll[owner][msg.sender], "not approved");
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(
        uint256 tokenId
    ) public view returns (address) {
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(
        address operator,
        bool approved
    ) external {
        _isApprovedForAll[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(
        address owner,
        address operator
    ) public view returns (bool) {
        return _isApprovedForAll[owner][operator];
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public {
        address owner = ownerOf(tokenId);
        require(owner == from, "transfer from wrong owner");
        require(
            msg.sender == owner || getApproved(tokenId) == msg.sender
                || isApprovedForAll(owner, msg.sender),
            "not authorized"
        );

        // clear approvals
        _tokenApprovals[tokenId] = address(0);

        _ownerOf[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    /**
     * @notice Burn tokenId. Allowed only for owner or approved.
     */
    function burn(
        uint256 tokenId
    ) external {
        address owner = ownerOf(tokenId);
        require(
            msg.sender == owner || getApproved(tokenId) == msg.sender
                || isApprovedForAll(owner, msg.sender),
            "not authorized to burn"
        );

        // remove ownership
        delete _ownerOf[tokenId];
        burned[tokenId] = true;

        emit Burned(msg.sender, tokenId);
        emit Transfer(owner, address(0), tokenId);
    }
}

/**
 * @title NFTRedeemerTest
 * @dev Foundry test contract for NFTNativeRedeemer.
 */
contract NFTRedeemerTest is Test {
    MockERC721Burnable mockNft;
    NFTRedeemer redeemer;

    address owner = address(0xABCD);
    address alice = address(0xBEEF);
    address bob = address(0xCAFE);
    address burner = address(0xDEAD);

    uint256 normalAmount = 1 ether;
    uint256 discountedAmount = 0.5 ether;

    function setUp() public {
        // Deploy mock NFT and redeemer
        mockNft = new MockERC721Burnable();

        // deploy redeemer as owner (we'll impersonate owner for owner-only calls)
        vm.prank(owner);
        redeemer = new NFTRedeemer(address(mockNft), normalAmount, discountedAmount, owner, burner);

        // mint a few example tokens to alice and bob
        // we'll use token ids that map to different bitmap slots
        uint256[] memory tokensAlice = new uint256[](3);
        tokensAlice[0] = 5;
        tokensAlice[1] = 4000;
        tokensAlice[2] = 20000;

        for (uint256 i = 0; i < tokensAlice.length; i++) {
            mockNft.mint(alice, tokensAlice[i]);
        }

        // bob gets token 50000 and also a non-discount token 100
        mockNft.mint(bob, 50000);
        mockNft.mint(bob, 100);

        // fund redeemer contract with some ETH to cover redemptions
        // we'll fund later on a per-test basis to make edge-case testing easier
    }

    /* ============ Helper utils ============ */

    function fundRedeemer(
        uint256 amount
    ) internal {
        // send ETH to redeemer
        vm.deal(address(this), amount);
        (bool sent,) = address(redeemer).call{value: amount}("");
        require(sent, "fund failed");
    }

    function assertBitSet(
        uint256 tokenId
    ) internal view {
        uint256 slot = tokenId >> 8;
        uint256 bit = tokenId & 0xFF;
        uint256 word = redeemer.discountBitmap(slot);
        // mask check
        assertTrue((word & (1 << bit)) != 0, "expected bit set");
        assertTrue(redeemer.isAlternate(tokenId), "expected isDiscounted true");
    }

    function assertBitUnset(
        uint256 tokenId
    ) internal view {
        uint256 slot = tokenId >> 8;
        uint256 bit = tokenId & 0xFF;
        uint256 word = redeemer.discountBitmap(slot);
        assertTrue((word & (1 << bit)) == 0, "expected bit unset");
        assertFalse(redeemer.isAlternate(tokenId), "expected isDiscounted false");
    }

    function assertBurned(
        uint256 tokenId
    ) internal view {
        assertEq(mockNft.ownerOf(tokenId), burner, "expected token burned");
    }

    /* ============ Tests ============ */

    function testOwnerCanSetDiscountsAndBitmapUpdated() public {
        uint256[] memory tokenIds = new uint256[](4);
        tokenIds[0] = 5;
        tokenIds[1] = 4000;
        tokenIds[2] = 20000;
        tokenIds[3] = 50000;

        // call setDiscountedBatch as owner
        vm.prank(owner);
        redeemer.setAlternateBatch(tokenIds, true);

        // verify bits set in correct slots
        assertBitSet(5);
        assertBitSet(4000);
        assertBitSet(20000);
        assertBitSet(50000);

        assertBitUnset(1);
        assertBitUnset(2000);
        assertBitUnset(40000);
        assertBitUnset(60000);

        // call setDiscounted as owner
        vm.startPrank(owner);
        redeemer.setAlternate(1, true);
        redeemer.setAlternate(2000, true);
        redeemer.setAlternate(40000, true);
        redeemer.setAlternate(60000, true);
        vm.stopPrank();

        // verify bits set in correct slots
        assertBitSet(1);
        assertBitSet(2000);
        assertBitSet(40000);
        assertBitSet(60000);

        assertBitUnset(2);
        assertBitUnset(2001);
        assertBitUnset(40002);
        assertBitUnset(60003);

        assertBitSet(5);
        assertBitSet(4000);
        assertBitSet(20000);
        assertBitSet(50000);
    }

    function testRedeemDiscountedSingleTokenPaysDiscountAndBurns() public {
        // set discount for token 5
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 5;
        vm.prank(owner);
        redeemer.setAlternateBatch(tokenIds, true);

        // alice must approve redeemer to burn her token
        vm.prank(alice);
        mockNft.approve(address(redeemer), 5);

        // fund redeemer with discounted amount
        fundRedeemer(discountedAmount);

        uint256 aliceBalanceBefore = alice.balance;
        // perform redeem as alice
        vm.prank(alice);
        redeemer.redeem(5, alice);

        // alice receives discountedAmount
        assertEq(alice.balance, aliceBalanceBefore + discountedAmount);

        // token should be burned (mock sets burned mapping true)
        assertBurned(5);
    }

    function testRedeemNonDiscountedSingleTokenPaysNormalAndBurns() public {
        // token 100 (bob) is not discounted by default
        // bob approve redeemer
        vm.prank(bob);
        mockNft.approve(address(redeemer), 100);

        // fund redeemer
        fundRedeemer(normalAmount);

        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        redeemer.redeem(100, bob);

        assertEq(bob.balance, bobBefore + normalAmount);
        assertBurned(100);
    }

    function testBatchRedeemMixedDiscountsPaysCorrectTotalAndBurnsAll() public {
        // Setup: mark 5 and 20000 as discounted, leave 4000 non-discounted, bob's 50000 discounted
        uint256[] memory toSet = new uint256[](3);
        toSet[0] = 5;
        toSet[1] = 20000;
        toSet[2] = 50000;
        vm.prank(owner);
        redeemer.setAlternateBatch(toSet, true);

        // Approve tokens to contract for burning
        vm.prank(alice);
        mockNft.setApprovalForAll(address(redeemer), true);
        vm.prank(bob);
        mockNft.setApprovalForAll(address(redeemer), true);

        // compute expected total
        uint256 totalExpected = discountedAmount + normalAmount + discountedAmount;

        // fund redeemer with the total expected
        fundRedeemer(totalExpected);

        uint256 aliceBefore = alice.balance;
        uint256 bobBefore = bob.balance;

        // perform batch redeem from alice (note: bob's token is owned by bob but burn requires approvals, burn is called by contract; to simplify we will call batch redeem from bob separately for his token)
        // Instead, perform two batch calls that correspond to each owner to match access checks.
        // Alice redeems 5 and 4000
        vm.startPrank(alice);
        redeemer.redeem(5, alice);
        redeemer.redeem(4000, alice);
        vm.stopPrank();

        // Bob redeems his token
        vm.prank(bob);
        redeemer.redeem(50000, bob);

        // Verify balances
        // Alice received discounted for 5 + normal for 4000
        assertEq(alice.balance, aliceBefore + discountedAmount + normalAmount);
        // Bob received discounted amount
        assertEq(bob.balance, bobBefore + discountedAmount);

        // All tokens burned
        assertBurned(5);
        assertBurned(4000);
        assertBurned(50000);
    }

    function testUnsetDiscountsWorks() public {
        // set then unset token 4000
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 4000;
        vm.prank(owner);
        redeemer.setAlternateBatch(tokenIds, true);

        // ensure set
        assertBitSet(4000);

        // unset
        vm.prank(owner);
        redeemer.setAlternateBatch(tokenIds, false);

        // ensure unset
        assertBitUnset(4000);
    }

    function testRedeemRevertsWhenInsufficientBalance() public {
        // mark token 5 discounted
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 5;
        vm.prank(owner);
        redeemer.setAlternateBatch(tokenIds, true);

        // approve
        vm.prank(alice);
        mockNft.approve(address(redeemer), 5);

        // Do NOT fund redeemer -> expect revert
        vm.prank(alice);
        vm.expectRevert(); // InsufficientContractBalance
        redeemer.redeem(5, alice);
    }

    function testPausablePreventsRedeem() public {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 5;
        vm.prank(owner);
        redeemer.setAlternateBatch(tokenIds, true);

        // approve
        vm.prank(alice);
        mockNft.approve(address(redeemer), 5);

        // pause contract
        vm.prank(owner);
        redeemer.pause();

        // try redeem -> should revert
        vm.prank(alice);
        vm.expectRevert(); // revert because whenNotPaused
        redeemer.redeem(5, alice);

        // unpause and succeed after funding
        vm.prank(owner);
        redeemer.unpause();

        fundRedeemer(discountedAmount);
        vm.prank(alice);
        redeemer.redeem(5, alice);
        assertBurned(5);
    }

    function testCannotSetDiscountBatchWithEmptyArray() public {
        uint256[] memory tokenIds = new uint256[](0);
        // Owner call with empty array throws in our implementation
        vm.prank(owner);
        vm.expectRevert();
        redeemer.setAlternateBatch(tokenIds, true);

        // nothing changed (check a known token remains unset)
        assertBitUnset(5);
    }

    function testSettingDiscountsForLargeDiverseIds() public {
        // choose diverse ids
        uint256[] memory tokenIds = new uint256[](7);
        tokenIds[0] = 1;
        tokenIds[1] = 600; // slot 2
        tokenIds[2] = 4095; // slot 15
        tokenIds[3] = 12000; // slot 46
        tokenIds[4] = 30000; // slot 117
        tokenIds[5] = 59999;
        tokenIds[6] = 79000;

        vm.prank(owner);
        redeemer.setAlternateBatch(tokenIds, true);

        // assert bits are set for each
        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertBitSet(tokenIds[i]);
        }

        // assert other bits are unset
        uint256[] memory unsetIds = new uint256[](7);
        unsetIds[0] = 2;
        unsetIds[1] = 601; // slot 2
        unsetIds[2] = 4096; // slot 15
        unsetIds[3] = 12005; // slot 46
        unsetIds[4] = 30002; // slot 117
        unsetIds[5] = 60001;
        unsetIds[6] = 100001;
        for (uint256 i = 0; i < unsetIds.length; i++) {
            assertBitUnset(unsetIds[i]);
        }
    }

    function testRedeemToOtherRecipient() public {
        // Alice approves redeemer
        vm.prank(alice);
        mockNft.approve(address(redeemer), 5);

        // Fund redeemer
        fundRedeemer(normalAmount);

        // Redeem to bob (not owner)
        uint256 bobBalanceBefore = bob.balance;
        vm.prank(alice);
        redeemer.redeem(5, bob);

        assertEq(bob.balance, bobBalanceBefore + normalAmount);
        assertBurned(5);
    }

    function testBatchRedeemToOtherRecipient() public {
        // Set discount for tokens
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 5;
        tokenIds[1] = 4000;
        vm.prank(owner);
        redeemer.setAlternateBatch(tokenIds, true);

        // Alice approves redeemer
        vm.prank(alice);
        mockNft.setApprovalForAll(address(redeemer), true);

        // Fund redeemer
        fundRedeemer(discountedAmount * 2);

        // Redeem batch to bob
        uint256 bobBalanceBefore = bob.balance;
        uint256[] memory batch = new uint256[](2);
        batch[0] = 5;
        batch[1] = 4000;
        vm.prank(alice);
        redeemer.redeemBatch(batch, bob);

        assertEq(bob.balance, bobBalanceBefore + discountedAmount * 2);
        assertBurned(5);
        assertBurned(4000);
    }

    function testRedeemToSelfAndOtherRecipientInBatch() public {
        // Set discount for one token
        vm.prank(owner);
        redeemer.setAlternate(5, true);

        // Alice approves redeemer
        vm.prank(alice);
        mockNft.setApprovalForAll(address(redeemer), true);

        // Fund redeemer
        fundRedeemer(discountedAmount + normalAmount);

        // Redeem batch to alice
        uint256 aliceBalanceBefore = alice.balance;
        uint256[] memory batch = new uint256[](2);
        batch[0] = 5;
        batch[1] = 4000;
        vm.prank(alice);
        redeemer.redeemBatch(batch, alice);

        assertEq(alice.balance, aliceBalanceBefore + discountedAmount + normalAmount);
        assertBurned(5);
        assertBurned(4000);
    }

    function testOwnerCanWithdrawFunds() public {
        // Fund redeemer contract with 3 ether
        uint256 fundAmount = 3 ether;
        uint256 withdrawAmount = 2 ether;
        fundRedeemer(fundAmount);

        // Attempt withdraw as non-owner
        vm.prank(bob);
        vm.expectRevert(); // Ownable: caller is not the owner
        redeemer.withdraw(withdrawAmount);

        // Record owner balance before withdrawal
        uint256 ownerBalanceBefore = owner.balance;

        // Withdraw 2 ether as owner
        vm.prank(owner);
        redeemer.withdraw(withdrawAmount);

        // Owner should receive withdrawn amount
        assertEq(owner.balance, ownerBalanceBefore + withdrawAmount);

        // Contract balance should decrease accordingly
        assertEq(address(redeemer).balance, fundAmount - withdrawAmount);
    }

    function testOwnerCanSetDiscountedAmount() public {
        uint256 newDiscounted = 0.25 ether;

        // Only owner can set
        vm.prank(bob);
        vm.expectRevert(); // Ownable: caller is not the owner
        redeemer.setAlternateRedemptionAmount(newDiscounted);

        // Owner sets discounted amount
        vm.prank(owner);
        redeemer.setAlternateRedemptionAmount(newDiscounted);

        assertEq(redeemer.alternateRedemptionAmount(), newDiscounted);
    }

    function testOwnerCanSetRedemptionAmount() public {
        uint256 newAmount = 2 ether;

        // Only owner can set
        vm.prank(alice);
        vm.expectRevert(); // Ownable: caller is not the owner
        redeemer.setBaseRedemptionAmount(newAmount);

        // Owner sets normal amount
        vm.prank(owner);
        redeemer.setBaseRedemptionAmount(newAmount);

        assertEq(redeemer.baseRedemptionAmount(), newAmount);
    }

    function testOwnerCanSetBurner() public {
        address newBurner = address(0xFEED);

        // Only owner can set
        vm.prank(bob);
        vm.expectRevert(); // Ownable: caller is not the owner
        redeemer.setBurner(newBurner);

        // Owner sets burner
        vm.prank(owner);
        redeemer.setBurner(newBurner);

        assertEq(redeemer.burner(), newBurner);
    }

    function testNonOwnerCannotSetDiscounts() public {
        // Bob tries to set a discount for token 5
        vm.prank(bob);
        vm.expectRevert(); // Ownable: caller is not the owner
        redeemer.setAlternate(5, true);
        assertBitUnset(5);

        // Alice tries to unset a discount for token 4000
        vm.prank(owner);
        redeemer.setAlternate(4000, true);
        assertBitSet(4000);

        vm.prank(alice);
        vm.expectRevert(); // Ownable: caller is not the owner
        redeemer.setAlternate(4000, false);
        assertBitSet(4000);
    }
}
