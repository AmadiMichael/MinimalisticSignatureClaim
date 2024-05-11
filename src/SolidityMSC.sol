// SPDX-License-Identifier: MIT
pragma solidity 0.8.x;

interface IERC20 {
    function transfer(address _to, uint256 _amount) external returns (bool success);
    function transferFrom(address _from, address _to, uint256 _amount) external returns (bool success);
}

contract MinimalisticSignatureClaim {
    error ClaimNotStarted();
    error ClaimOver();
    error ClaimedAlready();
    error InvalidSignature();
    error WrongOwner();
    error TransferFailed();

    address public immutable tokenAddress;
    address public immutable owner;
    uint256 public immutable start;
    uint256 public immutable deadline;

    constructor(address _tokenAddress, address _owner, uint256 _start, uint256 _deadline) {
        tokenAddress = _tokenAddress;
        owner = _owner;
        start = _start;
        deadline = _deadline;
    }

    function claim(address _to, uint256 _amount, uint8 _v, bytes32 _r, bytes32 _s) external {
        if (start > block.timestamp) revert ClaimNotStarted();
        if (deadline < block.timestamp) revert ClaimOver();

        bool _hasClaimed;
        assembly ("memory-safe") {
            _hasClaimed := sload(_to)
        }
        if (_hasClaimed) revert ClaimedAlready();

        bytes32 _messageHash = keccak256(abi.encode(block.chainid, address(this), _to, _amount));
        address _owner = ecrecover(_messageHash, _v, _r, _s);
        // skip check for sig malleability since a `other-half-of-curve` sig would revert when checking `_hasClaimed`
        if (_owner == address(0)) revert InvalidSignature();
        if (_owner != owner) revert WrongOwner();

        assembly ("memory-safe") {
            sstore(_to, true)
        }

        (bool success, bytes memory returndata) =
            tokenAddress.call(abi.encodeWithSelector(IERC20.transfer.selector, _to, _amount));
        if (!success || (returndata.length != 0 && abi.decode(returndata, (uint256)) != 1)) revert TransferFailed();
    }

    function hasClaimed(address _addr) external view returns (bool _hasClaimed) {
        assembly ("memory-safe") {
            _hasClaimed := sload(_addr)
        }
    }
}
