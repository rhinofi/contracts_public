// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.6.2;

import "./MFreezable.sol";

contract MockFreezable is MFreezable {

  bool frozen;

  function isFrozen() public view override returns (bool) {
    return frozen;
  }

  function validateFreezeRequest(uint256 requestTime) internal override {
  }

  function freeze() internal override {
    frozen = true;
  }

  function mockFreezing(bool _frozen) public {
    frozen = _frozen;
  }
}
