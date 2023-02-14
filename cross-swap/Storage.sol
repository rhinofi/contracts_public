// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "./Relayer.sol";

abstract contract Storage {
  uint256 private constant MAX_GAP = 2**32;

  // UserAddress => TokenAddress => amount
  mapping(address => mapping(address => uint256)) public userBalances;

  // TokenAddress => amount
  mapping(address => uint256) internal tokenReserves;

  mapping(address => uint256) public userNonces;

  address public paraswap;
  address public paraswapTransferProxy;

  mapping(bytes32 => bool) internal uniqueIds;

    // UserAddress => TokenAddress => Emergency Withdrawal timestamp
  mapping(address => mapping(address => uint256)) public emergencyWithdrawalRequests;

  uint256 public withdrawalDelay;

  Relayer public relayer;

  uint256[MAX_GAP - 4] private __gap;

  modifier withUniqueId(bytes32 id) {
    require(!uniqueIds[id], "DUPLICATE_ID");
    uniqueIds[id] = true;
    _;
  }
}
