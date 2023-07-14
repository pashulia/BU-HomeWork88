pragma solidity =0.5.16;

import './interfaces/IUniswapV2Pair.sol';
import './UniswapV2ERC20.sol';
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';
import './interfaces/IUniswapV2Factory.sol';
import './interfaces/IUniswapV2Callee.sol';

contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20 {
    using SafeMath  for uint;
    using UQ112x112 for uint224;

    // значение минимальной ликвидности
    uint public constant MINIMUM_LIQUIDITY = 10**3;
    // селектор функции trasfer ERC20
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public factory;
    address public token0;
    address public token1;

    // резервы токенов - обновляются после каждой операции (mint, burn, swap)

    uint112 private reserve0;           // использует один слот для хранения, доступный через getReserves
    uint112 private reserve1;           // использует один слот для хранения, доступный через getReserves
    uint32  private blockTimestampLast; // использует один слот для хранения, доступный через getReserves
    
    // кумулятивная цена - расчитывается перед первой сделкой в блоке

    uint public price0CumulativeLast; // += (reserve1 / reserve0) * (blockTimestamp - blockTimestampLast)
    uint public price1CumulativeLast; // += (reserve0 / reserve1) * (blockTimestamp - blockTimestampLast)
    uint public kLast; // reserve0 * reserve1, по состоянию непосредственно после последнего события ликвидности

    // защита от reentrancy
    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'UniswapV2: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    // возвращает текущие резервы и метку времени 
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'UniswapV2: TRANSFER_FAILED');
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

    // в конструкторе инициализируем адрес factory
    constructor() public {
        factory = msg.sender;
    }

    // вызывается один раз factory во время развертывания
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, 'UniswapV2: FORBIDDEN'); // тщательная проверка
        token0 = _token0;
        token1 = _token1;
    }

    // обновлять резервы и, при первом обращении в каждом блоке, устанавливать цены на аккумуляторы
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= uint112(-1) && balance1 <= uint112(-1), 'UniswapV2: OVERFLOW');
        // от timestamp берутся только последние 32 байта из 256
        // этого хватит примерно до 2106 года
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        // расчитываем сколько прошло времени с последнего вызова пары
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // желательно переполнение
        // если прошедшее время дольше 0, то есть этот вызов первый в этом блоке
        // и нас есть резервы токенов, то изменяем кумулятивную цену
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        // обновляем значение резервов
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        // обновляем значение времени
        blockTimestampLast = blockTimestamp;
        // синхронизируем резев0 и резерв1
        emit Sync(reserve0, reserve1);
    }

    // если комиссия включена, монетарная ликвидность эквивалентна 1/6 части роста sqrt(k)
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        // полуем адрес куда платить комиссию
        address feeTo = IUniswapV2Factory(factory).feeTo();
        // определяем включена комиссия или нет
        feeOn = feeTo != address(0);
        // получаем последнее значение K
        uint _kLast = kLast; // экономия газа
        // если комиссия включена, тидёт сложная математика для расчёта комиссии
        if (feeOn) {
            if (_kLast != 0) {
                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
                uint rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint numerator = totalSupply.mul(rootK.sub(rootKLast));
                    uint denominator = rootK.mul(5).add(rootKLast);
                    uint liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        }
        // иначе если значение kLast != 0, то есть это не первый вызов функции - устанавливаем в 0 
        else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // эта низкоуровневая функция должна вызываться из контракта, который выполняет важные проверки безопасности
    function mint(address to) external lock returns (uint liquidity) {
        // получаем текущие резервы
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        // получаем текущий реальный баланс токенов для контракта этой пары
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        // получаем разницу между текущим балансом и резервами
        uint amount0 = balance0.sub(_reserve0);
        uint amount1 = balance1.sub(_reserve1);

        // вызываем эту функцию, чтобы узнать включена ли комиссия
        // пока она не включена, так что feeOn сохраняется false
        bool feeOn = _mintFee(_reserve0, _reserve1);
        // экономия газа, должна быть определена здесь, так как totalSupplay может обновляться в _mintFee 
        uint _totalSupply = totalSupply; 
        // если эта пара только создана и totalSupply равен 0
        if (_totalSupply == 0) {
            // расчитываем сколько LP токенов получит тот, кто внёс ликвидность
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
            // это минимальная ликвидность, которая минтится на нулевой адрес для сложной математики и токеномики
           _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }
        require(liquidity > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED');
        // минтим ликвидность
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        // feeOn == false так, что это не выполняется
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        require(amount0Out > 0 || amount1Out > 0, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'UniswapV2: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;
        { // scope for _token{0,1}, avoids stack too deep errors
        address _token0 = token0;
        address _token1 = token1;
        require(to != _token0 && to != _token1, 'UniswapV2: INVALID_TO');
        if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
        if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
        if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
        uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
        require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2), 'UniswapV2: K');
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // сброс остатков баланса для соответсвия резервам
    function skim(address to) external lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)).sub(reserve0));
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)).sub(reserve1));
    }

    // force reserves to match balances
    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }
}
