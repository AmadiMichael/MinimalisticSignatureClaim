// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2 as console} from "forge-std/Test.sol";
import {MockERC20 as AbstractMockERC20} from "forge-std/mocks/MockERC20.sol";
import {BatchMinimalisticSignatureClaim} from "../../src/BatchMSC/BatchMSC.sol";

contract BatchMSCTest is Test {
    uint256 immutable START;
    uint256 immutable DEADLINE;

    uint256 ownerPrivateKey = uint256(keccak256("owner"));
    address owner = vm.addr(ownerPrivateKey);
    address user1 = vm.addr(uint256(keccak256("user1")));

    MockERC20 token;
    BatchMinimalisticSignatureClaim public batchMSC;

    constructor() {
        // time settings
        vm.warp(vm.unixTime() / 1_000);
        START = block.timestamp;
        DEADLINE = block.timestamp + 30 days;
    }

    function setUp() public virtual {
        vm.label(user1, "User1");
        vm.label(owner, "Owner");

        token = new MockERC20();
        token.initialize("MockERC20", "MERC20", 18);

        batchMSC = new BatchMinimalisticSignatureClaim(address(token), owner, START, DEADLINE);

        token.mint(address(batchMSC), type(uint256).max);
    }

    function _claim(uint256 signerPrivateKey, address user, uint256 amount, uint256 _nonce) internal {
        // generate sig for user to claim
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(signerPrivateKey, keccak256(abi.encode(block.chainid, address(batchMSC), user, amount, _nonce)));
        // claim
        batchMSC.claim(user, amount, _nonce, v, r, s);
    }

    function test_claim(uint256 _nonce) external {
        uint256 amount = 100_000 ether;

        uint256 userBalanceBefore = token.balanceOf(user1);
        uint256 claimContractBalanceBefore = token.balanceOf(address(batchMSC));

        _claim(ownerPrivateKey, user1, amount, _nonce);

        assertEq(token.balanceOf(user1), userBalanceBefore + amount);
        assertEq(token.balanceOf(address(batchMSC)), claimContractBalanceBefore - amount);
        assertTrue(batchMSC.hasClaimed(_nonce));
    }

    function testRevertsIfClaimNotStarted(uint256 _nonce) external {
        // move to a second before start time
        vm.warp(block.timestamp - 1);

        // try claim, expect revert with ClaimOver()
        vm.expectRevert(BatchMinimalisticSignatureClaim.ClaimNotStarted.selector);
        _claim(ownerPrivateKey, user1, 100_000 ether, _nonce);
    }

    function testRevertsIfClaimIsOver(uint256 _nonce) external {
        // move to 30 days and 1 second from now, 1 second ahead of deadline
        skip(30 days + 1);

        // try claim, expect revert with ClaimOver()
        vm.expectRevert(BatchMinimalisticSignatureClaim.ClaimOver.selector);
        _claim(ownerPrivateKey, user1, 100_000 ether, _nonce);
    }

    function testRevertsIfNonceHasBeenClaimedAlready(uint256 _nonce) external {
        // claim with user1
        _claim(ownerPrivateKey, user1, 100_000 ether, _nonce);

        // try claim again, should revert with ClaimedAlready()
        vm.expectRevert(BatchMinimalisticSignatureClaim.ClaimedAlready.selector);
        _claim(ownerPrivateKey, user1, 100_000 ether, _nonce);
    }

    function testRevertsIfSignatureIsInvalid(uint256 _nonce) external {
        uint256 amount = 100_000 ether;

        // generate sig for user to claim
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(ownerPrivateKey, keccak256(abi.encode(block.chainid, address(batchMSC), user1, amount, _nonce)));

        bytes32 value_over_curve_order = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

        // claim with invalid v, should revert with InvalidSignature()
        vm.expectRevert(BatchMinimalisticSignatureClaim.InvalidSignature.selector);
        batchMSC.claim(user1, amount, _nonce, 26, r, s);

        // claim with invalid r, should revert with InvalidSignature()
        vm.expectRevert(BatchMinimalisticSignatureClaim.InvalidSignature.selector);
        batchMSC.claim(user1, amount, _nonce, v, value_over_curve_order, s);

        // claim with invalid s, should revert with InvalidSignature()
        vm.expectRevert(BatchMinimalisticSignatureClaim.InvalidSignature.selector);
        batchMSC.claim(user1, amount, _nonce, v, r, value_over_curve_order);
    }

    function testRevertsIfSignatureRecoversToWrongSigner(uint256 _nonce) external {
        // try claim with wrong signer of signature, should revert with WrongOwner()
        vm.expectRevert(BatchMinimalisticSignatureClaim.WrongOwner.selector);
        _claim(ownerPrivateKey + 1, user1, 100_000 ether, _nonce);
    }

    function _batchClaim(
        uint256 signerPrivateKey,
        address[] memory users,
        uint256[] memory amounts,
        uint256 _startNonce
    ) internal {
        // generate sig for user to claim
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            signerPrivateKey, keccak256(abi.encode(block.chainid, address(batchMSC), users, amounts, _startNonce))
        );
        // claim
        batchMSC.batchClaim(users, amounts, _startNonce, v, r, s);
    }

    function testBatchClaim(address[512] calldata users, uint256[512] calldata amounts, uint256 _random) external {
        uint256 len = bound(_random, 1, 512);

        address[] memory _users = new address[](len);
        uint256[] memory _amounts = new uint256[](len);

        for (uint256 i; i < len; i++) {
            _amounts[i] = bound(amounts[i], 0, 100_000 ether);
            _users[i] = users[i];
        }

        _batchClaim(ownerPrivateKey, _users, _amounts, 0);
        _batchClaim(ownerPrivateKey, _users, _amounts, 512);
    }

    function testBatchClaimAftermathWorks(address[512] calldata users, uint256[512] calldata amounts, uint256 _random)
        external
    {
        uint256 len = 466;

        address[] memory _users = new address[](len);
        uint256[] memory _amounts = new uint256[](len);

        for (uint256 i; i < len; i++) {
            _amounts[i] = bound(amounts[i], 0, 100_000 ether);
            _users[i] = users[i];
        }

        _batchClaim(ownerPrivateKey, _users, _amounts, 0);
        _claim(ownerPrivateKey, user1, 100_000 ether, bound(_random, len, type(uint256).max));
    }

    function testBatchClaimRevertsIfEncounterUsedSingleNonce(
        address[512] calldata users,
        uint256[512] calldata amounts,
        uint256 _random
    ) external {
        uint256 len = bound(_random, 256, 512);

        address[] memory _users = new address[](len);
        uint256[] memory _amounts = new uint256[](len);

        for (uint256 i; i < len; i++) {
            _amounts[i] = bound(amounts[i], 0, 100_000 ether);
            _users[i] = users[i];
        }

        _claim(ownerPrivateKey, user1, 100_000 ether, bound(_random, 0, 255));

        vm.expectRevert(BatchMinimalisticSignatureClaim.ClaimedAlready.selector);
        _batchClaim(ownerPrivateKey, _users, _amounts, 0);
    }

    function testBatchClaimRevertsIfEncounterUsedBatchNonce(address[512] calldata users, uint256[512] calldata amounts)
        external
    {
        uint256 len = 512;

        address[] memory _users = new address[](len);
        uint256[] memory _amounts = new uint256[](len);

        for (uint256 i; i < len; i++) {
            _amounts[i] = bound(amounts[i], 0, 100_000 ether);
            _users[i] = users[i];
        }

        _batchClaim(ownerPrivateKey, _users, _amounts, 0);

        vm.expectRevert(BatchMinimalisticSignatureClaim.ClaimedAlready.selector);
        _batchClaim(ownerPrivateKey, _users, _amounts, 256);
    }

    function testBatchClaimRevertsIfInvalidNonce(address[512] calldata users, uint256[512] calldata amounts) external {
        uint256 len = 512;

        address[] memory _users = new address[](len);
        uint256[] memory _amounts = new uint256[](len);

        for (uint256 i; i < len; i++) {
            _amounts[i] = bound(amounts[i], 0, 100_000 ether);
            _users[i] = users[i];
        }

        vm.expectRevert(BatchMinimalisticSignatureClaim.InvalidStartNonce.selector);
        _batchClaim(ownerPrivateKey, _users, _amounts, 1);
    }
}

contract MockERC20 is AbstractMockERC20 {
    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}
