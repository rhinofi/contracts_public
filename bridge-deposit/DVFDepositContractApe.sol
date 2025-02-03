// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.4.22 <0.9.0;

import "./DVFDepositContract.sol";

interface ArbInfo {
    function configureAutomaticYield() external;
    function configureVoidYield() external;
    function configureDelegateYield(address delegate) external;
}

// Ape interface https://docs.apechain.com/native/Overview
enum YieldMode {
    AUTOMATIC,
    VOID,
    DELEGATE
}

/**
 * Support ApeChain yield configurations
 */
contract DVFDepositContractApe is DVFDepositContract {
  ArbInfo constant APE = ArbInfo(address(0x0000000000000000000000000000000000000065));


  function initialize() public override {
    super.initialize();
    APE.configureAutomaticYield();
  }

  function configureYield(YieldMode yieldMode, address delegate) external onlyOwner {
      if(yieldMode == YieldMode.AUTOMATIC) {
          APE.configureAutomaticYield();
      } else if(yieldMode == YieldMode.VOID) {
          APE.configureVoidYield();
      } else if(yieldMode == YieldMode.DELEGATE) {
          APE.configureDelegateYield(delegate);
      }
  }
}
