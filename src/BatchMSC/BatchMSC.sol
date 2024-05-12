// SPDX-License-Identifier: MIT
pragma solidity 0.8.x;

interface IERC20 {
    function transfer(address _to, uint256 _amount) external returns (bool success);
}

contract BatchMinimalisticSignatureClaim {
    error ClaimNotStarted();
    error ClaimOver();
    error ClaimedAlready();
    error InvalidSignature();
    error WrongOwner();
    error TransferFailed();
    error LengthMisMatch();
    error InvalidStartNonce();
    error InvalidLength();

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

    function claim(address _to, uint256 _amount, uint256 _nonce, uint8 _v, bytes32 _r, bytes32 _s) external {
        if (start > block.timestamp) revert ClaimNotStarted();
        if (deadline < block.timestamp) revert ClaimOver();

        if (!_consumeNonce(_nonce)) revert ClaimedAlready();

        bytes32 _messageHash = keccak256(abi.encode(block.chainid, address(this), _to, _amount, _nonce));
        _ecrecover(_messageHash, _v, _r, _s);

        _safeTransfer(tokenAddress, _to, _amount);
    }

    function _consumeNonce(uint256 _nonce) internal returns (bool _success) {
        assembly ("memory-safe") {
            let slot := div(_nonce, 256)
            let value := sload(slot)
            let offset := mod(_nonce, 256)

            _success := iszero(and(shl(offset, 0x01), value))

            if _success {
                let newValue := or(value, shl(offset, 0x01))
                sstore(slot, newValue)
            }
        }
    }

    function batchClaim(
        address[] calldata _tos,
        uint256[] calldata _amounts,
        uint256 _startNonce,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        if (start > block.timestamp) revert ClaimNotStarted();
        if (deadline < block.timestamp) revert ClaimOver();
        if (_startNonce % 256 != 0) revert InvalidStartNonce();
        if (_tos.length != _amounts.length) revert LengthMisMatch();
        if (_tos.length == 0) revert InvalidLength();

        if (!_batchConsumeNonce(_startNonce, _tos.length)) revert ClaimedAlready();

        bytes32 _messageHash = keccak256(abi.encode(block.chainid, address(this), _tos, _amounts, _startNonce));
        _ecrecover(_messageHash, _v, _r, _s);

        for (uint256 i; i < _tos.length; ++i) {
            _safeTransfer(tokenAddress, _tos[i], _amounts[i]);
        }
    }

    function _batchConsumeNonce(uint256 _startNonce, uint256 _len) internal returns (bool _success) {
        assembly ("memory-safe") {
            // get the start slot and end slot
            let currentSlot := div(_startNonce, 256)
            let lastSlotOffset := mod(_len, 256)
            let endSlot := add(sub(add(div(_len, 256), currentSlot), 0x01), gt(lastSlotOffset, 0x00))

            _success := true

            for {} iszero(gt(currentSlot, endSlot)) { currentSlot := add(currentSlot, 0x01) } {
                // if it's the last slot and does not use all bits in the slot
                switch and(eq(currentSlot, endSlot), gt(lastSlotOffset, 0))
                case 1 {
                    // get the upper bitsize to be untouched
                    let diff := sub(256, lastSlotOffset)

                    // get current slot value
                    let value := sload(currentSlot)

                    // if the relevant slot bits (bits[0:offset]) is not 0, return false
                    if shr(diff, shl(diff, value)) {
                        _success := false
                        break
                    }

                    // create a mask to set all the relevant slot bits (bits[0:offset]) to 1
                    let mask := shr(diff, shl(diff, not(0)))

                    // set to 1 and store new value
                    sstore(currentSlot, or(value, mask))
                }
                case 0 {
                    // since all bits in this slot would be used, if the current value is not 0, return false
                    if sload(currentSlot) {
                        _success := false
                        break
                    }

                    // else set all bits to true
                    sstore(currentSlot, not(0))
                }
            }
        }
    }

    function hasClaimed(uint256 _nonce) external view returns (bool) {
        return _nonceUsed(_nonce);
    }

    function _nonceUsed(uint256 _nonce) internal view returns (bool nonceUsed_) {
        assembly ("memory-safe") {
            let slot := div(_nonce, 256)
            let offset := mod(_nonce, 256)

            nonceUsed_ := shr(offset, and(shl(offset, 0x01), sload(slot)))
        }
    }

    function _safeTransfer(address _tokenAddress, address _to, uint256 _amount) private {
        (bool success, bytes memory returndata) =
            _tokenAddress.call(abi.encodeWithSelector(IERC20.transfer.selector, _to, _amount));
        if (!success || (returndata.length != 0 && abi.decode(returndata, (uint256)) != 1)) revert TransferFailed();
    }

    function _ecrecover(bytes32 _messageHash, uint8 _v, bytes32 _r, bytes32 _s) private view {
        address _owner = ecrecover(_messageHash, _v, _r, _s);
        // skip check for sig malleability since a `other-half-of-curve` sig would revert when checking `_hasClaimed`
        if (_owner == address(0)) revert InvalidSignature();
        if (_owner != owner) revert WrongOwner();
    }
}
