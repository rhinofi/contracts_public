// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.12;

import '@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol';

// TODO rename to PairBeacon
contract PairHolder is UpgradeableBeacon {
  uint public constant MIN_UPGRADE_DELAY = 14 days;
  uint public upgradeDelay;
  uint public implementationRequestTs;
  address public newImplementation;

  constructor(address implementation_) 
    UpgradeableBeacon(implementation_) { }

  function admin() external view returns (address) {
    return owner();
  }

  function changeAdmin(address _newAdmin) external {
    return transferOwnership(_newAdmin);
  }

  function upgradeTo(address _newImplementation) public override {
    require(
      upgradeDelay == 0 || implementationRequestTs + upgradeDelay >= block.timestamp,
      'UPGRADE_DELAY_NOT_REACHED'
    );

    super.upgradeTo(_newImplementation);
  }

  function requestUpgradeTo(address _newImplementation) public  onlyOwner{
    newImplementation = _newImplementation;
    implementationRequestTs = block.timestamp;
  }

  /**
   * @dev Set minimum upgrade delay, once this is set, it cannot be reduced to 0 anymore
   */
  function setUpgradeDelay(uint _upgradeDelay) external onlyOwner {
    require(_upgradeDelay >= MIN_UPGRADE_DELAY, 'DELAY_BELLOW_MIN');
    upgradeDelay = _upgradeDelay;
  }
}
