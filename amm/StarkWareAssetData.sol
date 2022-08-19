// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.6.12;

import './starkex/interfaces/IStarkEx.sol';

// Required functions from StarkWare TokenAssetData
/**
 * From StarkEx contracts:
 * https://github.com/starkware-libs/starkex-contracts/blob/0efa9ce324b04226de5dcd7a0139b109bca8f074/scalable-dex/contracts/src/interactions/TokenAssetData.sol#L9
 */
abstract contract StarkWareAssetData {
    bytes4 internal constant ETH_SELECTOR = bytes4(keccak256("ETH()"));

    // The selector follows the 0x20 bytes assetInfo.length field.
    uint256 internal constant SELECTOR_OFFSET = 0x20;
    uint256 internal constant SELECTOR_SIZE = 4;
    uint256 internal constant TOKEN_CONTRACT_ADDRESS_OFFSET = SELECTOR_OFFSET + SELECTOR_SIZE;

    function extractContractAddressFromAssetInfo(bytes memory assetInfo)
        private pure returns (address res) {
        uint256 offset = TOKEN_CONTRACT_ADDRESS_OFFSET;
        assembly {
            res := mload(add(assetInfo, offset))
        }
    }

    function extractTokenSelector(bytes memory assetInfo) internal pure
        returns (bytes4 selector) {
        assembly {
            selector := and(
                0xffffffff00000000000000000000000000000000000000000000000000000000,
                mload(add(assetInfo, SELECTOR_OFFSET))
            )
        }
    }

    function isEther(IStarkEx starkEx, uint256 assetType) internal view returns (bool) {
        return extractTokenSelector(starkEx.getAssetInfo(assetType)) == ETH_SELECTOR;
    }

    function extractContractAddress(IStarkEx starkEx, uint256 assetType) internal view returns (address) {
        return extractContractAddressFromAssetInfo(starkEx.getAssetInfo(assetType));
    }
}
