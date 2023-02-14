// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./VM.sol";
import "hardhat/console.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract RhinoVM is VM, AccessControl {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    constructor(address admin, address operator) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR_ROLE, address(this));
        _grantRole(OPERATOR_ROLE, operator);
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
