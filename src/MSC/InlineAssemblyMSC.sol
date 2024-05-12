// SPDX-License-Identifier: MIT
pragma solidity 0.8.x;

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
        address _tokenAddress = tokenAddress;
        address _owner = owner;
        uint256 _start = start;
        uint256 _deadline = deadline;

        assembly {
            // clean upper bits of input types not up to 256 bits
            _to := and(_to, 0xffffffffffffffffffffffffffffffffffffffff)
            _v := and(_v, 0xff)

            // if _start has not reached, revert
            if gt(_start, timestamp()) {
                mstore(0x00, 0xb0e9ce1e) // error ClaimNotStarted()
                revert(0x1c, 0x04)
            }

            // if _deadline has passed, revert
            if lt(_deadline, timestamp()) {
                mstore(0x00, 0x549c1c34) // error ClaimOver()
                revert(0x1c, 0x04)
            }

            // _to is used as the storage slot for if an address has claimed or not
            if sload(_to) {
                mstore(0x00, 0x15675431) // error ClaimedAlready()
                revert(0x1c, 0x04)
            }

            // abi.encode (chainid, address(this), _to, _amount) and hash to get the hash expected to have been signed
            mstore(0x00, chainid())
            mstore(0x20, address())
            mstore(0x40, _to)
            mstore(0x60, _amount)
            let _messageHash := keccak256(0x00, 0x80)

            // ecrecover, _signer is default as address(0)
            let _signer

            // abi encode call parameters into memory and make call.
            mstore(0x00, _messageHash)
            mstore(0x20, _v)
            mstore(0x40, _r)
            mstore(0x60, _s)
            pop(staticcall(gas(), 0x01, 0x00, 0x80, 0x00, 0x00))

            // if returndata > 0 then set the returned data as the recovered signer
            if returndatasize() {
                returndatacopy(0x00, 0x00, returndatasize())
                _signer := mload(0x00)
            }

            // if no return data (only case where _signer can still be address(0) at this point) revert
            if iszero(_signer) {
                mstore(0x00, 0x8baa579f)
                revert(0x1c, 0x04) // error InvalidSignature()
            }
            // if _signer not same as _owner, revert
            if sub(_signer, _owner) {
                mstore(0x00, 0x5d652eb1) // error WrongOwner()
                revert(0x1c, 0x04)
            }

            // set _to to have claimed
            sstore(_to, true)

            // make safeTransfer of _amount to _to
            mstore(0x00, 0xa9059cbb)
            mstore(0x20, _to)
            mstore(0x40, _amount)
            if or(
                and(returndatasize(), sub(mload(0x00), 0x01)),
                iszero(call(gas(), _tokenAddress, 0x00, 0x1c, 0x44, 0x00, 0x20))
            ) {
                mstore(0x00, 0x90b8ec18)
                revert(0x1c, 0x04) // error TransferFailed()
            }
        }
    }

    function hasClaimed(address _addr) external view returns (bool) {
        assembly {
            // clean upper bits of input types not up to 256 bits
            _addr := and(_addr, 0xffffffffffffffffffffffffffffffffffffffff)

            mstore(0x00, sload(_addr))
            return(0x00, 0x20)
        }
    }
}
