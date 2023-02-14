// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "./Swap.sol";

/**
 * Deversifi escrow contract for performing swaps and bridging while maintaining user's custody
 */
contract DVFCrossSwap is Swap {
  // constructor() initializer { }

  function initialize(
    address _admin,
    address _paraswap,
    address _paraswapTransferProxy
  ) external initializer {
    __DVFAccessControl_init(_admin);
    __Swap_init(_admin, _paraswap, _paraswapTransferProxy);
  }
}
