// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

library StarkLib {
  function fromQuantized(uint _quantum, uint256 quantizedAmount)
      internal pure returns (uint256 amount) {
      amount = quantizedAmount * _quantum;
      require(amount / _quantum == quantizedAmount, "DEQUANTIZATION_OVERFLOW");
  }

  function toQuantizedUnsafe(uint _quantum, uint256 amount)
      internal pure returns (uint256 quantizedAmount) {
      quantizedAmount = amount / _quantum;
  }

  function toQuantized(uint _quantum, uint256 amount)
      internal pure returns (uint256 quantizedAmount) {
      if (amount == 0) {
        return 0;
      }
      require(amount % _quantum == 0, "INVALID_AMOUNT_TO_QUANTIZED");
      quantizedAmount = amount / _quantum;
  }

  function truncate(uint quantum, uint amount) internal pure returns (uint) {
    if (amount == 0) {
      return 0;
    }
    require(amount > quantum, 'DVF: TRUNCATE_AMOUNT_LOWER_THAN_QUANTUM');
    return amount - (amount % quantum);
  }
}
