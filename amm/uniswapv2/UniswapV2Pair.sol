// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.12;

import './UniswapV2ERC20.sol';
import '../starkex/libraries/StarkLib.sol';
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';
import './interfaces/IUniswapV2Factory.sol';
import './interfaces/IUniswapV2Callee.sol';
import '../PairStorage.sol';

interface IMigrator {
    // Return the desired amount of liquidity token that the migrator wants.
    function desiredLiquidity() external view returns (uint256);
}

abstract contract UniswapV2Pair is UniswapV2ERC20, PairStorage {
    using SafeMathUniswap  for uint;
    using StarkLib  for uint;
    using UQ112x112 for uint224;

    uint public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    modifier lock() {
        require(unlocked == 1, 'DVF_AMM: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32) {
        return (reserve0, reserve1, 0);
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'DVF_AMM: TRANSFER_FAILED');
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1) internal virtual {
        require(factory == address(0), 'DVF_AMM: FORBIDDEN');
        super.initialize();
        factory = msg.sender;
        token0 = _token0;
        token1 = _token1;
        unlocked = 1;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, 'DVF_AMM: OVERFLOW');
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        emit Sync(reserve0, reserve1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) public virtual lock returns (uint liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        (uint lpQuantum, uint token0Quantum, uint token1Quantum) = getQuantums();
        (uint balance0, uint balance1) = balances();
        // Quantize to ensure we do not respect the percision higher than our quant
        uint amount0 = token0Quantum.toQuantizedUnsafe(balance0.sub(_reserve0));
        uint amount1 = token1Quantum.toQuantizedUnsafe(balance1.sub(_reserve1));
        uint reserve0Quantized = token0Quantum.toQuantizedUnsafe(_reserve0);
        uint reserve1Quantized = token1Quantum.toQuantizedUnsafe(_reserve1);

        uint _totalSupply = lpQuantum.toQuantizedUnsafe(totalSupply); 
        if (_totalSupply == 0) {
            address migrator = IUniswapV2Factory(factory).migrator();
            if (msg.sender == migrator) {
                liquidity = IMigrator(migrator).desiredLiquidity();
                require(liquidity > 0 && liquidity != type(uint256).max, "Bad desired liquidity");
            } else {
                require(migrator == address(0), "Must not have migrator");
                liquidity = calculateInitialLiquidity(amount0, amount1, lpQuantum);
                _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
            }
        } else {
            liquidity = Math.min(amount0.mul(_totalSupply) / reserve0Quantized, amount1.mul(_totalSupply) / reserve1Quantized);
            liquidity = lpQuantum.fromQuantized(liquidity);
        }

        require(liquidity > 0, 'DVF_AMM: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(to, liquidity);

        _update(balance0, balance1);
        emit Mint(msg.sender, amount0, amount1);
    }

    function calculateInitialLiquidity(uint amount0, uint amount1, uint lpQuantum) internal pure returns(uint liquidity) {
      liquidity = Math.sqrt(amount0.mul(amount1).mul(lpQuantum).mul(lpQuantum)).sub(MINIMUM_LIQUIDITY);
      // Truncate
      liquidity = liquidity.sub(liquidity % lpQuantum);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) public virtual lock returns (uint amount0, uint amount1) {
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings
        (uint balance0, uint balance1) = balances();
        // truncate to ensure cannot burn with higher percision than quantum
        uint liquidity = lpQuantum.truncate(balanceOf[address(this)]);

        uint _totalSupply = totalSupply; // gas savings 
        amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 || amount1 > 0, 'DVF_AMM: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        (balance0, balance1) = balances();

        _update(balance0, balance1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) public virtual lock {
        require(amount0Out > 0 || amount1Out > 0, 'DVF_AMM: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'DVF_AMM: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;
        { // scope for _token{0,1}, avoids stack too deep errors
        address _token0 = token0;
        address _token1 = token1;
        require(to != _token0 && to != _token1, 'DVF_AMM: INVALID_TO');
        (,uint token0Quantum, uint token1Quantum) = getQuantums();
        if (amount0Out > 0) {
          amount0Out = token0Quantum.truncate(amount0Out);
          _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
        }
        if (amount1Out > 0) {
          amount1Out = token1Quantum.truncate(amount1Out);
          _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
        }
        if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
        (balance0, balance1) = balances();
        }
        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'DVF_AMM: INSUFFICIENT_INPUT_AMOUNT');

        // validate K ratio
        validateK(balance0, balance1, _reserve0, _reserve1);

        _update(balance0, balance1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function validateK(uint balance0, uint balance1, uint _reserve0, uint _reserve1) internal view {
      (,uint token0Quantum, uint token1Quantum) = getQuantums();
      uint balance0Adjusted = token0Quantum.toQuantizedUnsafe(balance0);
      uint balance1Adjusted = token1Quantum.toQuantizedUnsafe(balance1);
      uint reserve0Adjusted = token0Quantum.toQuantizedUnsafe(_reserve0);
      uint reserve1Adjusted = token1Quantum.toQuantizedUnsafe(_reserve1);
      require(balance0Adjusted.mul(balance1Adjusted) >= reserve0Adjusted.mul(reserve1Adjusted), 'DVF_AMM: K');
    }

    // force balances to match reserves
    function skim(address to) public virtual lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        (uint balance0, uint balance1) = balances();
        _safeTransfer(_token0, to, balance0.sub(reserve0));
        _safeTransfer(_token1, to, balance1.sub(reserve1));
    }

    // force reserves to match balances
    function sync() public virtual lock {
        (uint balance0, uint balance1) = balances();
        _update(balance0, balance1);
    }

    function balances() internal view virtual returns (uint balance0, uint balance1) {
      balance0 = IERC20Uniswap(token0).balanceOf(address(this));
      balance1 = IERC20Uniswap(token1).balanceOf(address(this));
    }

    // Abstract methods
    function getQuantums() public view virtual returns (uint, uint, uint);
}
