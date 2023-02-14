// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract Relayer is AccessControl {

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE , msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    function relay(
        address relayer,
        bytes calldata data
    ) external payable onlyRole(OPERATOR_ROLE) returns (bytes memory result)
    {
        result = Address.functionCallWithValue(relayer, data, msg.value, "RELAYER_FAILURE");
        return result;
    }
}