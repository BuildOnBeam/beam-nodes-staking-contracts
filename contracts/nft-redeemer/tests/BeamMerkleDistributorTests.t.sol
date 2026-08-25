// SPDX-License-Identifier: MIT
// run via `forge test -vvv --match-path "contracts/nft-redeemer/tests/BeamMerkleDistributorTests.t.sol"`
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {BeamMerkleDistributor} from "../BeamMerkleDistributor.sol";
import {IBeamMerkleDistributor} from "../interfaces/IBeamMerkleDistributor.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {}

    function mint(
        address to,
        uint256 amount
    ) external {
        _mint(to, amount);
    }
}

contract BeamMerkleDistributorTest is Test {
    MockERC20 token;
    MockERC20 otherToken;
    BeamMerkleDistributor distributor;

    address owner = address(0xABCD);
    address alice = address(0xBEEF);
    address bob = address(0xCAFE);
    address carol = address(0xC0DE);
    address dave = address(0xD00D);
    string initialURI = "ipfs://beam-merkle";

    uint256 claimAmount = 100e18;
    uint256 endTime;
    bytes32 leaf;

    function _hashPair(
        bytes32 a,
        bytes32 b
    ) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function _leafFor(
        address account,
        uint256 amount
    ) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encodePacked(account, amount))));
    }

    function _fourLeafRootAndProofForAlice(
        uint256 aliceAmount,
        uint256 bobAmount,
        uint256 carolAmount,
        uint256 daveAmount
    ) internal view returns (bytes32 root, bytes32[2] memory proofItems) {
        bytes32 aliceLeaf = _leafFor(alice, aliceAmount);
        bytes32 bobLeaf = _leafFor(bob, bobAmount);
        bytes32 carolLeaf = _leafFor(carol, carolAmount);
        bytes32 daveLeaf = _leafFor(dave, daveAmount);

        bytes32 leftNode = _hashPair(aliceLeaf, bobLeaf);
        bytes32 rightNode = _hashPair(carolLeaf, daveLeaf);
        root = _hashPair(leftNode, rightNode);

        proofItems[0] = bobLeaf;
        proofItems[1] = rightNode;
    }

    function setUp() public {
        token = new MockERC20();
        otherToken = new MockERC20();

        leaf = keccak256(bytes.concat(keccak256(abi.encodePacked(alice, claimAmount))));
        endTime = block.timestamp + 7 days;

        distributor = new BeamMerkleDistributor(address(token), leaf, endTime, owner, initialURI);
    }

    function testConstructorSetsInitialState() public view {
        assertEq(distributor.token(), address(token));
        assertEq(distributor.merkleRoot(), leaf);
        assertEq(distributor.endTime(), endTime);
        assertEq(distributor.owner(), owner);
        assertEq(distributor.uri(), initialURI);
        assertTrue(distributor.paused());
    }

    function testSetMerkleRootOnlyOwner() public {
        bytes32 newRoot = keccak256("new-root");

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        distributor.setMerkleRoot(newRoot);

        vm.prank(owner);
        distributor.setMerkleRoot(newRoot);
        assertEq(distributor.merkleRoot(), newRoot);
    }

    function testSetEndTimeOnlyOwner() public {
        uint256 newEndTime = endTime + 1 days;

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        distributor.setEndTime(newEndTime);

        vm.prank(owner);
        distributor.setEndTime(newEndTime);
        assertEq(distributor.endTime(), newEndTime);
    }

    function testPauseAndUnpauseOnlyOwner() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        distributor.unpause();

        vm.prank(owner);
        distributor.unpause();
        assertFalse(distributor.paused());

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        distributor.pause();

        vm.prank(owner);
        distributor.pause();
        assertTrue(distributor.paused());
    }

    function testClaimRevertsWhilePaused() public {
        bytes32[] memory proof = new bytes32[](0);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        distributor.claim(alice, claimAmount, proof);
    }

    function testClaimSuccess() public {
        token.mint(address(distributor), claimAmount);

        vm.prank(owner);
        distributor.unpause();

        bytes32[] memory proof = new bytes32[](0);
        uint256 aliceBalanceBefore = token.balanceOf(alice);

        vm.expectEmit(true, true, true, true);
        emit IBeamMerkleDistributor.Claimed(alice, claimAmount);

        distributor.claim(alice, claimAmount, proof);

        assertTrue(distributor.isClaimed(alice));
        assertEq(token.balanceOf(alice) - aliceBalanceBefore, claimAmount);
        assertEq(token.balanceOf(address(distributor)), 0);
    }

    function testClaimRevertsAlreadyClaimed() public {
        token.mint(address(distributor), claimAmount * 2);

        vm.prank(owner);
        distributor.unpause();

        bytes32[] memory proof = new bytes32[](0);
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        distributor.claim(alice, claimAmount, proof);
        assertEq(token.balanceOf(alice) - aliceBalanceBefore, claimAmount);

        vm.expectRevert(IBeamMerkleDistributor.AlreadyClaimed.selector);
        distributor.claim(alice, claimAmount, proof);
    }

    function testClaimRevertsInvalidProof() public {
        token.mint(address(distributor), claimAmount);

        vm.prank(owner);
        distributor.unpause();

        bytes32[] memory proof = new bytes32[](0);

        vm.expectRevert(IBeamMerkleDistributor.InvalidProof.selector);
        distributor.claim(alice, claimAmount + 1, proof);
    }

    function testClaimRevertsForAddressOtherThanProof() public {
        token.mint(address(distributor), claimAmount);

        vm.prank(owner);
        distributor.unpause();

        bytes32[] memory proof = new bytes32[](0);

        vm.expectRevert(IBeamMerkleDistributor.InvalidProof.selector);
        distributor.claim(bob, claimAmount, proof);
    }

    function testClaimRevertsWhenInsufficientTokenBalance() public {
        token.mint(address(distributor), claimAmount - 1);

        vm.prank(owner);
        distributor.unpause();

        bytes32[] memory proof = new bytes32[](0);

        vm.expectRevert();
        distributor.claim(alice, claimAmount, proof);

        // Revert must roll back claim state even though assignment happens before transfer.
        assertFalse(distributor.isClaimed(alice));
    }

    function testClaimSetsOnlyClaimantAsClaimed() public {
        uint256 bobAmount = 77e18;
        bytes32 aliceLeaf = _leafFor(alice, claimAmount);
        bytes32 bobLeaf = _leafFor(bob, bobAmount);
        bytes32 root = _hashPair(aliceLeaf, bobLeaf);

        BeamMerkleDistributor localDistributor =
            new BeamMerkleDistributor(address(token), root, block.timestamp + 1 days, owner, "");

        token.mint(address(localDistributor), claimAmount + bobAmount);

        vm.prank(owner);
        localDistributor.unpause();

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bobLeaf;

        localDistributor.claim(alice, claimAmount, proof);

        assertTrue(localDistributor.isClaimed(alice));
        assertFalse(localDistributor.isClaimed(bob));
    }

    function testSetMerkleRootAfterClaimDoesNotAllowSecondClaimForSameAddress() public {
        token.mint(address(distributor), claimAmount * 3);

        vm.prank(owner);
        distributor.unpause();

        bytes32[] memory proof = new bytes32[](0);
        uint256 aliceBalanceBefore = token.balanceOf(alice);

        distributor.claim(alice, claimAmount, proof);
        assertEq(token.balanceOf(alice) - aliceBalanceBefore, claimAmount);

        bytes32 newRoot = _leafFor(alice, claimAmount * 2);
        vm.prank(owner);
        distributor.setMerkleRoot(newRoot);

        vm.expectRevert(IBeamMerkleDistributor.AlreadyClaimed.selector);
        distributor.claim(alice, claimAmount * 2, proof);
    }

    function testSetMerkleRootEnablesClaimForNewAddress() public {
        uint256 bobAmount = 55e18;
        token.mint(address(distributor), claimAmount + bobAmount);

        vm.prank(owner);
        distributor.unpause();

        bytes32[] memory proof = new bytes32[](0);
        distributor.claim(alice, claimAmount, proof);

        bytes32 bobRoot = _leafFor(bob, bobAmount);
        vm.prank(owner);
        distributor.setMerkleRoot(bobRoot);

        uint256 bobBalanceBefore = token.balanceOf(bob);
        uint256 distributorBalanceBefore = token.balanceOf(address(distributor));
        distributor.claim(bob, bobAmount, proof);

        assertTrue(distributor.isClaimed(alice));
        assertTrue(distributor.isClaimed(bob));
        assertEq(token.balanceOf(bob) - bobBalanceBefore, bobAmount);
        assertEq(distributorBalanceBefore - token.balanceOf(address(distributor)), bobAmount);
    }

    function testSupportsInterfaceBehavior() public view {
        assertTrue(distributor.supportsInterface(type(IERC165).interfaceId));
        assertTrue(distributor.supportsInterface(type(IBeamMerkleDistributor).interfaceId));
        assertFalse(distributor.supportsInterface(type(Ownable).interfaceId));
        assertFalse(distributor.supportsInterface(type(IERC20).interfaceId));
        assertFalse(distributor.supportsInterface(0x12345678));
    }

    function testClaimRevertsAfterEndTime() public {
        token.mint(address(distributor), claimAmount);

        vm.prank(owner);
        distributor.unpause();

        vm.warp(endTime + 1);

        bytes32[] memory proof = new bytes32[](0);

        vm.expectRevert(IBeamMerkleDistributor.ClaimWindowFinished.selector);
        distributor.claim(alice, claimAmount, proof);
    }

    function testSetPastEndTimeImmediatelyBlocksClaims() public {
        token.mint(address(distributor), claimAmount);

        vm.prank(owner);
        distributor.unpause();

        vm.prank(owner);
        distributor.setEndTime(block.timestamp - 1);

        bytes32[] memory proof = new bytes32[](0);

        vm.expectRevert(IBeamMerkleDistributor.ClaimWindowFinished.selector);
        distributor.claim(alice, claimAmount, proof);
    }

    function testClaimCanBeSubmittedByThirdPartyCaller() public {
        token.mint(address(distributor), claimAmount);

        vm.prank(owner);
        distributor.unpause();

        bytes32[] memory proof = new bytes32[](0);
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 distributorBalanceBefore = token.balanceOf(address(distributor));

        vm.prank(bob);
        distributor.claim(alice, claimAmount, proof);

        assertTrue(distributor.isClaimed(alice));
        assertEq(token.balanceOf(alice) - aliceBalanceBefore, claimAmount);
        assertEq(distributorBalanceBefore - token.balanceOf(address(distributor)), claimAmount);
    }

    function testClaimSucceedsAtExactEndTime() public {
        token.mint(address(distributor), claimAmount);

        vm.prank(owner);
        distributor.unpause();

        vm.warp(endTime);

        bytes32[] memory proof = new bytes32[](0);
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 distributorBalanceBefore = token.balanceOf(address(distributor));

        distributor.claim(alice, claimAmount, proof);

        assertTrue(distributor.isClaimed(alice));
        assertEq(token.balanceOf(alice) - aliceBalanceBefore, claimAmount);
        assertEq(distributorBalanceBefore - token.balanceOf(address(distributor)), claimAmount);
    }

    function testClaimZeroAmountIfInMerkleRoot() public {
        bytes32 zeroLeaf = _leafFor(alice, 0);
        BeamMerkleDistributor localDistributor = new BeamMerkleDistributor(
            address(token), zeroLeaf, block.timestamp + 1 days, owner, ""
        );

        vm.prank(owner);
        localDistributor.unpause();

        bytes32[] memory proof = new bytes32[](0);
        uint256 aliceBalanceBefore = token.balanceOf(alice);

        localDistributor.claim(alice, 0, proof);

        assertTrue(localDistributor.isClaimed(alice));
        assertEq(token.balanceOf(alice), aliceBalanceBefore);
    }

    function testWithdrawRevertsWithNoBalance() public {
        vm.prank(owner);
        vm.expectRevert(IBeamMerkleDistributor.NoBalanceToWithdraw.selector);
        distributor.withdraw(address(token));
    }

    function testWithdrawNativeRevertsWithNoBalance() public {
        vm.prank(owner);
        vm.expectRevert(IBeamMerkleDistributor.NoBalanceToWithdraw.selector);
        distributor.withdraw(address(0));
    }

    function testWithdrawOnlyOwner() public {
        uint256 amount = 1e18;
        otherToken.mint(address(distributor), amount);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        distributor.withdraw(address(otherToken));
    }

    function testWithdrawNativeOnlyOwner() public {
        uint256 amount = 1e18;
        vm.deal(address(distributor), amount);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        distributor.withdraw(address(0));
    }

    function testWithdrawSucceedsWhilePaused() public {
        uint256 amount = 2e18;
        otherToken.mint(address(distributor), amount);

        vm.prank(owner);
        distributor.withdraw(address(otherToken));

        assertEq(otherToken.balanceOf(address(distributor)), 0);
        assertEq(otherToken.balanceOf(owner), amount);
    }

    function testWithdrawTransfersEntireBalanceAndEmits() public {
        uint256 amount = 50e18;
        otherToken.mint(address(distributor), amount);

        vm.expectEmit(true, true, true, true);
        emit IBeamMerkleDistributor.Withdrawn(address(otherToken), amount, owner);

        vm.prank(owner);
        distributor.withdraw(address(otherToken));

        assertEq(otherToken.balanceOf(address(distributor)), 0);
        assertEq(otherToken.balanceOf(owner), amount);
    }

    function testWithdrawNativeTransfersEntireBalanceAndEmits() public {
        uint256 amount = 3 ether;
        vm.deal(address(distributor), amount);

        uint256 ownerBalanceBefore = owner.balance;

        vm.expectEmit(true, true, true, true);
        emit IBeamMerkleDistributor.Withdrawn(address(0), amount, owner);

        vm.prank(owner);
        distributor.withdraw(address(0));

        assertEq(address(distributor).balance, 0);
        assertEq(owner.balance - ownerBalanceBefore, amount);
    }

    function testFuzzClaimSuccessWithBoundedAmount(
        uint96 fuzzAmount
    ) public {
        uint256 amount = bound(uint256(fuzzAmount), 1, 1e30);
        bytes32 root = keccak256(bytes.concat(keccak256(abi.encodePacked(alice, amount))));
        BeamMerkleDistributor localDistributor =
            new BeamMerkleDistributor(address(token), root, block.timestamp + 7 days, owner, "");

        token.mint(address(localDistributor), amount);

        vm.prank(owner);
        localDistributor.unpause();

        bytes32[] memory proof = new bytes32[](0);
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 distributorBalanceBefore = token.balanceOf(address(localDistributor));
        localDistributor.claim(alice, amount, proof);

        assertTrue(localDistributor.isClaimed(alice));
        assertEq(token.balanceOf(alice) - aliceBalanceBefore, amount);
        assertEq(distributorBalanceBefore - token.balanceOf(address(localDistributor)), amount);
    }

    function testFuzzClaimRevertsInvalidProofForDifferentAmount(
        uint96 fuzzAmount
    ) public {
        uint256 differentAmount = bound(uint256(fuzzAmount), 1, 1e30);
        vm.assume(differentAmount != claimAmount);

        token.mint(address(distributor), claimAmount);

        vm.prank(owner);
        distributor.unpause();

        bytes32[] memory proof = new bytes32[](0);
        vm.expectRevert(IBeamMerkleDistributor.InvalidProof.selector);
        distributor.claim(alice, differentAmount, proof);
    }

    function testFuzzWithdrawTransfersEntireBalance(
        uint96 fuzzAmount
    ) public {
        uint256 amount = bound(uint256(fuzzAmount), 1, 1e30);
        otherToken.mint(address(distributor), amount);

        vm.prank(owner);
        distributor.withdraw(address(otherToken));

        assertEq(otherToken.balanceOf(address(distributor)), 0);
        assertEq(otherToken.balanceOf(owner), amount);
    }

    function testFuzzOwnerCanSetEndTime(
        uint40 offset
    ) public {
        uint256 newEndTime = block.timestamp + uint256(bound(uint256(offset), 1, 365 days));

        vm.prank(owner);
        distributor.setEndTime(newEndTime);

        assertEq(distributor.endTime(), newEndTime);
    }

    function testFuzzThirdPartyCallerClaimRoutesFundsToBeneficiary(
        uint96 fuzzAmount,
        address caller
    ) public {
        uint256 amount = bound(uint256(fuzzAmount), 1, 1e30);
        vm.assume(caller != address(0));
        vm.assume(caller != alice);

        bytes32 root = _leafFor(alice, amount);
        BeamMerkleDistributor localDistributor =
            new BeamMerkleDistributor(address(token), root, block.timestamp + 1 days, owner, "");

        token.mint(address(localDistributor), amount);

        vm.prank(owner);
        localDistributor.unpause();

        bytes32[] memory proof = new bytes32[](0);
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 callerBalanceBefore = token.balanceOf(caller);
        uint256 distributorBalanceBefore = token.balanceOf(address(localDistributor));

        vm.prank(caller);
        localDistributor.claim(alice, amount, proof);

        assertTrue(localDistributor.isClaimed(alice));
        assertEq(token.balanceOf(alice) - aliceBalanceBefore, amount);
        assertEq(token.balanceOf(caller), callerBalanceBefore);
        assertEq(distributorBalanceBefore - token.balanceOf(address(localDistributor)), amount);
    }

    function testFuzzRootRotationKeepsClaimStateAndAllowsNewAddress(
        uint96 aliceAmountFuzz,
        uint96 bobAmountFuzz,
        uint96 carolAmountFuzz,
        bool bobClaimsBeforeRotation
    ) public {
        uint256 aliceAmount = bound(uint256(aliceAmountFuzz), 1, 1e30);
        uint256 bobAmount = bound(uint256(bobAmountFuzz), 1, 1e30);
        uint256 carolAmount = bound(uint256(carolAmountFuzz), 1, 1e30);

        bytes32 aliceLeaf = _leafFor(alice, aliceAmount);
        bytes32 bobLeaf = _leafFor(bob, bobAmount);
        bytes32 rootOne = _hashPair(aliceLeaf, bobLeaf);

        BeamMerkleDistributor localDistributor =
            new BeamMerkleDistributor(address(token), rootOne, block.timestamp + 1 days, owner, "");

        token.mint(address(localDistributor), aliceAmount + bobAmount + carolAmount);

        vm.prank(owner);
        localDistributor.unpause();

        bytes32[] memory aliceProof = new bytes32[](1);
        aliceProof[0] = bobLeaf;
        bytes32[] memory bobProof = new bytes32[](1);
        bobProof[0] = aliceLeaf;

        localDistributor.claim(alice, aliceAmount, aliceProof);
        if (bobClaimsBeforeRotation) {
            localDistributor.claim(bob, bobAmount, bobProof);
        }

        bytes32 rootTwo = _leafFor(carol, carolAmount);
        vm.prank(owner);
        localDistributor.setMerkleRoot(rootTwo);

        bytes32[] memory emptyProof = new bytes32[](0);
        uint256 carolBalanceBefore = token.balanceOf(carol);
        localDistributor.claim(carol, carolAmount, emptyProof);

        assertEq(token.balanceOf(carol) - carolBalanceBefore, carolAmount);
        assertTrue(localDistributor.isClaimed(carol));

        vm.expectRevert(IBeamMerkleDistributor.AlreadyClaimed.selector);
        localDistributor.claim(alice, aliceAmount, emptyProof);

        if (bobClaimsBeforeRotation) {
            vm.expectRevert(IBeamMerkleDistributor.AlreadyClaimed.selector);
            localDistributor.claim(bob, bobAmount, emptyProof);
        }
    }

    function testFuzzClaimSuccessWithNonEmptyProof(
        uint96 aliceAmountFuzz,
        uint96 bobAmountFuzz,
        bool claimAlice
    ) public {
        uint256 aliceAmount = bound(uint256(aliceAmountFuzz), 1, 1e30);
        uint256 bobAmount = bound(uint256(bobAmountFuzz), 1, 1e30);

        bytes32 aliceLeaf = keccak256(bytes.concat(keccak256(abi.encodePacked(alice, aliceAmount))));
        bytes32 bobLeaf = keccak256(bytes.concat(keccak256(abi.encodePacked(bob, bobAmount))));
        bytes32 root = _hashPair(aliceLeaf, bobLeaf);

        BeamMerkleDistributor localDistributor =
            new BeamMerkleDistributor(address(token), root, block.timestamp + 1 days, owner, "");

        token.mint(address(localDistributor), aliceAmount + bobAmount);

        vm.prank(owner);
        localDistributor.unpause();

        bytes32[] memory proof = new bytes32[](1);
        address claimant = claimAlice ? alice : bob;
        uint256 claimableAmount = claimAlice ? aliceAmount : bobAmount;
        proof[0] = claimAlice ? bobLeaf : aliceLeaf;
        uint256 claimantBalanceBefore = token.balanceOf(claimant);
        uint256 distributorBalanceBefore = token.balanceOf(address(localDistributor));

        localDistributor.claim(claimant, claimableAmount, proof);

        assertTrue(localDistributor.isClaimed(claimant));
        assertEq(token.balanceOf(claimant) - claimantBalanceBefore, claimableAmount);
        assertEq(
            distributorBalanceBefore - token.balanceOf(address(localDistributor)), claimableAmount
        );
    }

    function testClaimRevertsWithTamperedSiblingProof() public {
        uint256 aliceAmount = 25e18;
        uint256 bobAmount = 40e18;

        bytes32 aliceLeaf = keccak256(bytes.concat(keccak256(abi.encodePacked(alice, aliceAmount))));
        bytes32 bobLeaf = keccak256(bytes.concat(keccak256(abi.encodePacked(bob, bobAmount))));
        bytes32 root = _hashPair(aliceLeaf, bobLeaf);

        BeamMerkleDistributor localDistributor =
            new BeamMerkleDistributor(address(token), root, block.timestamp + 1 days, owner, "");

        token.mint(address(localDistributor), aliceAmount + bobAmount);

        vm.prank(owner);
        localDistributor.unpause();

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(uint256(bobLeaf) ^ uint256(1));

        vm.expectRevert(IBeamMerkleDistributor.InvalidProof.selector);
        localDistributor.claim(alice, aliceAmount, proof);
    }

    function testFuzzClaimSuccessWithDepthTwoProof(
        uint96 aliceAmountFuzz,
        uint96 bobAmountFuzz,
        uint96 carolAmountFuzz,
        uint96 daveAmountFuzz
    ) public {
        uint256 aliceAmount = bound(uint256(aliceAmountFuzz), 1, 1e30);
        uint256 bobAmount = bound(uint256(bobAmountFuzz), 1, 1e30);
        uint256 carolAmount = bound(uint256(carolAmountFuzz), 1, 1e30);
        uint256 daveAmount = bound(uint256(daveAmountFuzz), 1, 1e30);

        (bytes32 root, bytes32[2] memory proofItems) =
            _fourLeafRootAndProofForAlice(aliceAmount, bobAmount, carolAmount, daveAmount);

        BeamMerkleDistributor localDistributor =
            new BeamMerkleDistributor(address(token), root, block.timestamp + 1 days, owner, "");

        token.mint(address(localDistributor), aliceAmount + bobAmount + carolAmount + daveAmount);

        vm.prank(owner);
        localDistributor.unpause();

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = proofItems[0];
        proof[1] = proofItems[1];
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 distributorBalanceBefore = token.balanceOf(address(localDistributor));

        localDistributor.claim(alice, aliceAmount, proof);

        assertTrue(localDistributor.isClaimed(alice));
        assertEq(token.balanceOf(alice) - aliceBalanceBefore, aliceAmount);
        assertEq(distributorBalanceBefore - token.balanceOf(address(localDistributor)), aliceAmount);
    }

    function testFuzzTwoUserClaimsDifferentAmountsDepthOne(
        uint96 aliceAmountFuzz,
        uint96 bobAmountFuzz,
        bool aliceClaimsFirst
    ) public {
        uint256 aliceAmount = bound(uint256(aliceAmountFuzz), 1, 1e30);
        uint256 bobAmount = bound(uint256(bobAmountFuzz), 1, 1e30);

        bytes32 aliceLeaf = _leafFor(alice, aliceAmount);
        bytes32 bobLeaf = _leafFor(bob, bobAmount);
        bytes32 root = _hashPair(aliceLeaf, bobLeaf);

        BeamMerkleDistributor localDistributor =
            new BeamMerkleDistributor(address(token), root, block.timestamp + 1 days, owner, "");

        token.mint(address(localDistributor), aliceAmount + bobAmount);

        vm.prank(owner);
        localDistributor.unpause();

        bytes32[] memory aliceProof = new bytes32[](1);
        aliceProof[0] = bobLeaf;

        bytes32[] memory bobProof = new bytes32[](1);
        bobProof[0] = aliceLeaf;

        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 bobBalanceBefore = token.balanceOf(bob);
        uint256 distributorBalanceBefore = token.balanceOf(address(localDistributor));

        if (aliceClaimsFirst) {
            localDistributor.claim(alice, aliceAmount, aliceProof);
            localDistributor.claim(bob, bobAmount, bobProof);
        } else {
            localDistributor.claim(bob, bobAmount, bobProof);
            localDistributor.claim(alice, aliceAmount, aliceProof);
        }

        assertTrue(localDistributor.isClaimed(alice));
        assertTrue(localDistributor.isClaimed(bob));
        assertEq(token.balanceOf(alice) - aliceBalanceBefore, aliceAmount);
        assertEq(token.balanceOf(bob) - bobBalanceBefore, bobAmount);
        assertEq(
            distributorBalanceBefore - token.balanceOf(address(localDistributor)),
            aliceAmount + bobAmount
        );
    }

    function testFuzzTwoUserClaimThenSecondWrongAmountReverts(
        uint96 aliceAmountFuzz,
        uint96 bobAmountFuzz,
        uint96 wrongBobAmountFuzz
    ) public {
        uint256 aliceAmount = bound(uint256(aliceAmountFuzz), 1, 1e30);
        uint256 bobAmount = bound(uint256(bobAmountFuzz), 1, 1e30);
        uint256 wrongBobAmount = bound(uint256(wrongBobAmountFuzz), 1, 1e30);
        vm.assume(wrongBobAmount != bobAmount);

        bytes32 aliceLeaf = _leafFor(alice, aliceAmount);
        bytes32 bobLeaf = _leafFor(bob, bobAmount);
        bytes32 root = _hashPair(aliceLeaf, bobLeaf);

        BeamMerkleDistributor localDistributor =
            new BeamMerkleDistributor(address(token), root, block.timestamp + 1 days, owner, "");

        token.mint(address(localDistributor), aliceAmount + bobAmount);

        vm.prank(owner);
        localDistributor.unpause();

        bytes32[] memory aliceProof = new bytes32[](1);
        aliceProof[0] = bobLeaf;

        bytes32[] memory bobProof = new bytes32[](1);
        bobProof[0] = aliceLeaf;

        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 distributorBalanceBefore = token.balanceOf(address(localDistributor));
        localDistributor.claim(alice, aliceAmount, aliceProof);

        assertTrue(localDistributor.isClaimed(alice));
        assertEq(token.balanceOf(alice) - aliceBalanceBefore, aliceAmount);
        assertEq(distributorBalanceBefore - token.balanceOf(address(localDistributor)), aliceAmount);

        vm.expectRevert(IBeamMerkleDistributor.InvalidProof.selector);
        localDistributor.claim(bob, wrongBobAmount, bobProof);
    }

    function testClaimRevertsWithTamperedDepthTwoProof() public {
        uint256 aliceAmount = 10e18;
        uint256 bobAmount = 20e18;
        uint256 carolAmount = 30e18;
        uint256 daveAmount = 40e18;

        (bytes32 root, bytes32[2] memory proofItems) =
            _fourLeafRootAndProofForAlice(aliceAmount, bobAmount, carolAmount, daveAmount);

        BeamMerkleDistributor localDistributor =
            new BeamMerkleDistributor(address(token), root, block.timestamp + 1 days, owner, "");

        token.mint(address(localDistributor), aliceAmount + bobAmount + carolAmount + daveAmount);

        vm.prank(owner);
        localDistributor.unpause();

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = proofItems[0];
        proof[1] = bytes32(uint256(proofItems[1]) ^ uint256(1));

        vm.expectRevert(IBeamMerkleDistributor.InvalidProof.selector);
        localDistributor.claim(alice, aliceAmount, proof);
    }
}
