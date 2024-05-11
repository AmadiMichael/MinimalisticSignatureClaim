// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2 as console} from "forge-std/Test.sol";
import {MockERC20 as AbstractMockERC20} from "forge-std/mocks/MockERC20.sol";

abstract contract BaseMSCTest is Test {
    uint256 immutable START;
    uint256 immutable DEADLINE;

    uint256 ownerPrivateKey = uint256(keccak256("owner"));
    address owner = vm.addr(ownerPrivateKey);
    address user1 = vm.addr(uint256(keccak256("user1")));

    MockERC20 token;
    IMinimalisticSignatureClaim public minimalisticSignatureClaim;

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

        minimalisticSignatureClaim = IMinimalisticSignatureClaim(_deployAndReturnMSC());

        token.mint(address(minimalisticSignatureClaim), 100_000 ether);
    }

    // IMPLEMENTED IN INHERITING CONTRACTS
    function _deployAndReturnMSC() internal virtual returns (address);

    function _claim(uint256 signerPrivateKey, address user, uint256 amount) internal {
        // generate sig for user to claim
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            signerPrivateKey, keccak256(abi.encode(block.chainid, address(minimalisticSignatureClaim), user, amount))
        );
        // claim
        minimalisticSignatureClaim.claim(user, amount, v, r, s);
    }

    function test_claim() external {
        uint256 amount = 100_000 ether;

        uint256 userBalanceBefore = token.balanceOf(user1);
        uint256 claimContractBalanceBefore = token.balanceOf(address(minimalisticSignatureClaim));

        _claim(ownerPrivateKey, user1, amount);

        assertEq(token.balanceOf(user1), userBalanceBefore + amount);
        assertEq(token.balanceOf(address(minimalisticSignatureClaim)), claimContractBalanceBefore - amount);
        assertTrue(minimalisticSignatureClaim.hasClaimed(user1));
    }

    function testRevertsIfClaimNotStarted() external {
        // move to a second before start time
        vm.warp(block.timestamp - 1);

        // try claim, expect revert with ClaimOver()
        vm.expectRevert(IMinimalisticSignatureClaim.ClaimNotStarted.selector);
        _claim(ownerPrivateKey, user1, 100_000 ether);
    }

    function testRevertsIfClaimIsOver() external {
        // move to 30 days and 1 second from now, 1 second ahead of deadline
        skip(30 days + 1);

        // try claim, expect revert with ClaimOver()
        vm.expectRevert(IMinimalisticSignatureClaim.ClaimOver.selector);
        _claim(ownerPrivateKey, user1, 100_000 ether);
    }

    function testRevertsIfUserHasClaimedAlready() external {
        // claim with user1
        _claim(ownerPrivateKey, user1, 100_000 ether);

        // try claim again, should revert with ClaimedAlready()
        vm.expectRevert(IMinimalisticSignatureClaim.ClaimedAlready.selector);
        _claim(ownerPrivateKey, user1, 100_000 ether);
    }

    function testRevertsIfSignatureIsInvalid() external {
        uint256 amount = 100_000 ether;

        // generate sig for user to claim
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            ownerPrivateKey, keccak256(abi.encode(block.chainid, address(minimalisticSignatureClaim), user1, amount))
        );

        bytes32 value_over_curve_order = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

        // claim with invalid v, should revert with InvalidSignature()
        vm.expectRevert(IMinimalisticSignatureClaim.InvalidSignature.selector);
        minimalisticSignatureClaim.claim(user1, amount, 26, r, s);

        // claim with invalid r, should revert with InvalidSignature()
        vm.expectRevert(IMinimalisticSignatureClaim.InvalidSignature.selector);
        minimalisticSignatureClaim.claim(user1, amount, v, value_over_curve_order, s);

        // claim with invalid s, should revert with InvalidSignature()
        vm.expectRevert(IMinimalisticSignatureClaim.InvalidSignature.selector);
        minimalisticSignatureClaim.claim(user1, amount, v, r, value_over_curve_order);
    }

    function testRevertsIfSignatureRecoversToWrongSigner() external {
        // try claim with wrong signer of signature, should revert with WrongOwner()
        vm.expectRevert(IMinimalisticSignatureClaim.WrongOwner.selector);
        _claim(ownerPrivateKey + 1, user1, 100_000 ether);
    }
}

contract MockERC20 is AbstractMockERC20 {
    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}

interface IMinimalisticSignatureClaim {
    error ClaimNotStarted();
    error ClaimOver();
    error ClaimedAlready();
    error InvalidSignature();
    error WrongOwner();
    error TransferFailed();

    function claim(address _to, uint256 _amount, uint8 _v, bytes32 _r, bytes32 _s) external;
    function hasClaimed(address _addr) external view returns (bool _hasClaimed);
}
