// SPDX-License-Identifier: MIT
// run via `forge test -vvv --match-path "contracts/nft-redeemer/tests/NFTClaimRedeemerTests.t.sol"`
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {NFTClaimRedeemer, NFTRedeemer} from "../NFTClaimRedeemer.sol";
import {MockERC721Burnable} from "./NFTRedeemerTests.t.sol";

/**
 * @title NFTClaimRedeemerTest
 * @dev Foundry test contract for NFTClaimRedeemer.
 */
contract NFTClaimRedeemerTest is Test {
    MockERC721Burnable mockNft;
    NFTClaimRedeemer claimRedeemer;

    address owner = address(0xABCD);
    address alice = address(0xBEEF);
    address bob = address(0xCAFE);
    address burner = address(0xDEAD);

    uint256 normalAmount = 1 ether;
    uint256 discountedAmount = 0.3 ether;

    function setUp() public {
        // Deploy mock NFT and redeemer
        mockNft = new MockERC721Burnable();

        // deploy redeemer as owner (we'll impersonate owner for owner-only calls)
        vm.prank(owner);
        claimRedeemer =
            new NFTClaimRedeemer(address(mockNft), normalAmount, discountedAmount, owner, burner);
    }

    /* ============ Helper utils ============ */

    function _fundRedeemer(
        uint256 amount
    ) internal {
        // send ETH to redeemer
        vm.deal(address(this), amount);
        (bool sent,) = address(claimRedeemer).call{value: amount}("");
        require(sent, "fund failed");
    }

    /* ============ Tests ============ */

    function testOwnerCanSetClaim() public {
        uint256 claimAmount = 2 ether;
        vm.prank(owner);
        claimRedeemer.setClaim(alice, claimAmount);
        assertEq(claimRedeemer.claims(alice), claimAmount);
    }

    function testNonOwnerCannotSetClaim() public {
        vm.prank(bob);
        vm.expectRevert();
        claimRedeemer.setClaim(alice, 1 ether);
    }

    function testOwnerCanSetClaimBatch() public {
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        uint256[] memory values = new uint256[](2);
        values[0] = 1 ether;
        values[1] = 2 ether;

        vm.prank(owner);
        claimRedeemer.setClaimBatch(accounts, values);
        assertEq(claimRedeemer.claims(alice), 1 ether);
        assertEq(claimRedeemer.claims(bob), 2 ether);
    }

    function testSetClaimBatchRevertsOnInputMismatch() public {
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        uint256[] memory values = new uint256[](1);
        values[0] = 1 ether;

        vm.prank(owner);
        vm.expectRevert(NFTClaimRedeemer.InputMismatch.selector);
        claimRedeemer.setClaimBatch(accounts, values);
    }

    function testRedeemUnclaimedSuccess() public {
        uint256 claimAmount = 1.5 ether;

        // Owner sets a claim for Alice
        vm.prank(owner);
        claimRedeemer.setClaim(alice, claimAmount);

        // Fund the contract
        _fundRedeemer(claimAmount);

        uint256 aliceBalanceBefore = alice.balance;

        // Alice redeems her claim
        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit NFTClaimRedeemer.RedeemedUnclaimed(alice, claimAmount);
        claimRedeemer.redeemUnclaimed(alice);
        vm.stopPrank();

        // Check Alice's balance
        assertEq(
            alice.balance, aliceBalanceBefore + claimAmount, "Alice should receive the claim amount"
        );

        // Verify claim is reset to 0 by trying to redeem again
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(NFTClaimRedeemer.NoClaimableTokens.selector, alice));
        claimRedeemer.redeemUnclaimed(alice);
    }

    function testRedeemUnclaimedToDifferentRecipient() public {
        uint256 claimAmount = 1.5 ether;

        // Owner sets a claim for Alice
        vm.prank(owner);
        claimRedeemer.setClaim(alice, claimAmount);

        // Fund the contract
        _fundRedeemer(claimAmount);

        uint256 bobBalanceBefore = bob.balance;

        // Alice redeems her claim, sending the funds to Bob
        vm.startPrank(alice);
        vm.expectEmit(true, true, true, true);
        emit NFTClaimRedeemer.RedeemedUnclaimed(alice, claimAmount);
        claimRedeemer.redeemUnclaimed(bob);
        vm.stopPrank();

        // Check Bob's balance
        assertEq(bob.balance, bobBalanceBefore + claimAmount, "Bob should receive the claim amount");
    }

    function testRedeemUnclaimedRevertsForNoTokens() public {
        // Bob has no claim set
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(NFTClaimRedeemer.NoClaimableTokens.selector, bob));
        claimRedeemer.redeemUnclaimed(bob);
    }

    function testRedeemUnclaimedRevertsForInsufficientBalance() public {
        uint256 claimAmount = 2 ether;

        // Owner sets a claim for Alice
        vm.prank(owner);
        claimRedeemer.setClaim(alice, claimAmount);

        // Fund the contract with less than the claim amount
        _fundRedeemer(claimAmount - 1);

        // Alice attempts to redeem
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                NFTRedeemer.InsufficientContractBalance.selector,
                claimAmount,
                address(claimRedeemer).balance
            )
        );
        claimRedeemer.redeemUnclaimed(alice);
    }

    function testPausablePreventsRedeemUnclaimed() public {
        uint256 claimAmount = 1 ether;
        vm.prank(owner);
        claimRedeemer.setClaim(alice, claimAmount);

        // Pause contract
        vm.prank(owner);
        claimRedeemer.pause();

        // Try to redeem -> should revert
        vm.prank(alice);
        vm.expectRevert();
        claimRedeemer.redeemUnclaimed(alice);

        // Unpause and redeem should succeed
        vm.prank(owner);
        claimRedeemer.unpause();

        _fundRedeemer(claimAmount);
        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        claimRedeemer.redeemUnclaimed(alice);
        assertEq(alice.balance, aliceBalanceBefore + claimAmount);
    }

    function testSetClaimBatchSuccess() public {
        // Set claims for Alice and Bob
        address[] memory accounts = new address[](2);
        accounts[0] = alice;
        accounts[1] = bob;

        uint256[] memory values = new uint256[](2);
        values[0] = 1 ether;
        values[1] = 2 ether;

        vm.prank(owner);
        claimRedeemer.setClaimBatch(accounts, values);

        // Fund contract
        _fundRedeemer(3 ether);

        // Alice redeems
        uint256 aliceBalanceBefore = alice.balance;
        vm.prank(alice);
        claimRedeemer.redeemUnclaimed(alice);
        assertEq(alice.balance, aliceBalanceBefore + values[0]);

        // Bob redeems
        uint256 bobBalanceBefore = bob.balance;
        vm.prank(bob);
        claimRedeemer.redeemUnclaimed(bob);
        assertEq(bob.balance, bobBalanceBefore + values[1]);

        // Contract balance should be 0
        assertEq(address(claimRedeemer).balance, 0);
    }
}
