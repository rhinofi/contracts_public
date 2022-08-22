// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.12;

interface IPairHolder {
  function pairByteCode() external pure returns (bytes memory);
  function pairCodeHash() external pure returns (bytes32);
}
