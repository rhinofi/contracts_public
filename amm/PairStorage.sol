// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.6.12;

abstract contract PairStorage {
  uint public constant lpQuantum = 1000;
  uint32 internal constant unsignedInt22 = 4194303;
  // If going for upgradables - allow for extra storage here
  uint internal constant GAP_LENGTH = 2**32;

  // Pair
  address public factory;
  address public token0;
  address public token1;

  uint internal price0CumulativeLast_UNUSED;
  uint internal price1CumulativeLast_UNUSED;
  uint internal kLast_UNUSED;

  uint internal unlocked;

  // PairOverlay
  uint internal syncLpChange;
  uint internal token0ExpectedBalance;
  uint internal token1ExpectedBalance;
  uint internal nonce;

  // Starkware values to be set
  uint internal lpAssetId;
  uint internal token0AssetId;
  uint internal token0Quanatum;
  uint internal token1AssetId;
  uint internal token1Quanatum;

  uint112 internal reserve0;           // uses single storage slot, accessible via getReserves
  uint112 internal reserve1;           // uses single storage slot, accessible via getReserves
  uint32  internal blockTimestampLast_UNUSED;  // uses a single storage slot

  address internal weth;

  // 0 - nothing to do, 
  // 1 - mint or mint+swap
  // 2 - burn or burn+swap  
  // 3 - swap only
  uint8 internal starkWareState;
  bool public isLayer2Live;

  // track current vault
  uint256 public currentVault;

  // Reserved storage for extensions
  // additional variables added above _gap and gap size must be reduced
  // https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
  uint256[GAP_LENGTH - 1] _gap;
}
