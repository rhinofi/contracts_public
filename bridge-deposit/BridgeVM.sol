// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * VM contract to execute calldata in a sandbox
 */
contract BridgeVM is Ownable {
  using SafeERC20 for IERC20;

  error CallFailed(uint256 index, address target, bytes result);

  struct Call {
    address target;
    uint256 value;
    bytes data;
  }

  function execute(Call[] calldata datas) external payable onlyOwner {
    for (uint i=0; i<datas.length; i++) {
      (bool success, bytes memory result) = payable(datas[i].target).call{value: datas[i].value}(datas[i].data);
      if (!success) {
        revert CallFailed({
          index: i,
          target: datas[i].target,
          result: result
        });
      }
    }
  }

  function withdrawVmFunds(address token) external {
    uint256 balance;
    if (token != address(0)) {
      balance = IERC20(token).balanceOf(address(this));
      if (balance > 0) {
        IERC20(token).safeTransfer(owner(), balance);
      }
    }

    balance = address(this).balance;
    if (balance > 0) {
      payable(owner()).call{value: balance}("");
    }
  }

  /**
   * @dev allow receiving native funds in case any failure returned funds back
   * to this contract
   */
  receive() external payable { }
}
