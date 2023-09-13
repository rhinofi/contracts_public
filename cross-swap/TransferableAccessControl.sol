// SPDX-License-Identifier: GPL3-only

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";

abstract contract TransferableAccessControl is AccessControl{
    function transferRole(bytes32 role, address account) public virtual {
        require(account != _msgSender(), 'TransferableAccessControl: Can not transfer to self');
        require(hasRole(role, _msgSender()), 'TransferableAccessControl: sender must have role to transfer');
        grantRole(role, account);
        revokeRole(role, _msgSender());
    }
}