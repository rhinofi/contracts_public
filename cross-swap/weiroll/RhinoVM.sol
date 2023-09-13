// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./VM.sol";
import "./../TransferableAccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RhinoVM is VM, TransferableAccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, address(this));
    }

    function revertIfBalanceNotZero(address token) public view {
        require(
            IERC20(token).balanceOf(address(this)) == 0,
            "RhinoVM: Balance not zero");
    }
  
    function executeRawCalldata(address target, bytes calldata data) 
        public onlyRole(OPERATOR_ROLE)
        returns (bytes memory)
    {
        (bool success, bytes memory result) = target.call(data);
        require(success, "RhinoVM: Failed to execute raw calldata");
        return result;
    }

    function execute(bytes32[] calldata commands, bytes[] memory state)
        public onlyRole(OPERATOR_ROLE)
        payable
        returns (bytes[] memory)
    {
        return _execute(commands, state);
    }
}
