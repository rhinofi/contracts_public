// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

pragma experimental ABIEncoderV2;


contract WeirollHelpers
{
    struct BalancerExitPoolRequest {
        address[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    struct BalancerJoinPoolRequest {
        address[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

/*

    Exact Tokens Join
        userData ABI
            ['uint256', 'uint256[]', 'uint256']
        userData
            [EXACT_TOKENS_IN_FOR_BPT_OUT, amountsIn, minimumBPT]
*/
    function buildArray2(uint256 a, uint256 b) external pure returns (uint256[] memory result) {
        result = new uint256[](2);
        result[0] = a;
        result[1] = b;
    }
    
    function buildArray3(uint256 a, uint256 b, uint256 c) external pure returns (uint256[] memory result) {
        result = new uint256[](3);
        result[0] = a;
        result[1] = b;
        result[2] = c;
    }
    function buildBalancerJoinPoolRequest(address[] calldata assets, uint256[] calldata maxAmountsIn, bool fromInternalBalance,  uint256 a, uint256[] calldata b, uint256 c) external pure returns (BalancerJoinPoolRequest memory request){
        request.assets = assets;
        request.maxAmountsIn = maxAmountsIn;
        request.userData = abi.encode(a,b,c);
        request.fromInternalBalance = fromInternalBalance;
    }

    function buildBalancerExitUserData(address[] calldata assets, uint256[] calldata minAmountsOut, bool toInternalBalance,  uint256 a, uint256 b, uint256 c) external pure returns (BalancerExitPoolRequest memory request){
        request.assets = assets;
        request.minAmountsOut = minAmountsOut;
        request.userData = abi.encode(a,b,c);
        request.toInternalBalance = toInternalBalance;
    }

    function buildCurveAddLiquiditCallData(uint256 amounts1, uint256 amounts2, uint256 min_mint_amount, bool use_eth) external pure returns (bytes memory) {
        return abi.encodeWithSignature("add_liquidity(uint256[2],uint256,bool)",[amounts1, amounts2],min_mint_amount, use_eth);
    }

    function bytesAsUint256(bytes calldata data) external pure returns (uint256 result) {
        assembly {
            let freeMemPtr := mload(0x40)
            calldatacopy(freeMemPtr, data.offset, 0x20)
            result := mload(freeMemPtr)
        }
    }
}