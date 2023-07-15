pragma solidity =0.5.16;

import './interfaces/IUniswapV2Factory.sol';
import './UniswapV2Pair.sol';

contract UniswapV2Factory is IUniswapV2Factory {
    // на этот адрес в будущем может отправлятся 0.05% комиссии
    address public feeTo;
    // это адресб который устанавливает значение feeTo
    address public feeToSetter;

    // словарь с пулами
    // (адрес token0 => (адрес token1 => адрес паоы))
    mapping(address => mapping(address => address)) public getPair;
    // массив с адресами всех пар
    address[] public allPairs;

    // событие создание пары
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    // в конструкторе установлен адрес feeToSetter
    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }

    // возвращает кол-во всех пар
    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    // создаёт новую пару 
    // tokenA и tokenB - адрес токенов
    // возвращает адрес пары
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        // проверка, что tokenA и tokenB - разные токены
        require(tokenA != tokenB, 'UniswapV2: IDENTICAL_ADDRESSES');
        // чтобы нельзя было создать две разных пары из двух одинаковых токенов,
        // делаем так, чтобы адрес token0 всегда был меньше, чем адрес toke1
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        // проверка, что token0 не нулевой адрес
        require(token0 != address(0), 'UniswapV2: ZERO_ADDRESS');
        // проверка, что такой пары ещё не создано
        require(getPair[token0][token1] == address(0), 'UniswapV2: PAIR_EXISTS'); // single check is sufficient
        // получаем байткод контракта пары
        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        // расчитываем соль для адреса из адресов токенов
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        // деплоим контракт
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        // инициализируем созданую пару значениями адресами token0 и token1
        IUniswapV2Pair(pair).initialize(token0, token1);
        // добавляем в словарь адрес пары для этих токенов
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        // добовляем в массив адрес новой пары
        allPairs.push(pair);
        // делаем событие
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    // установка комиссии для протокола
    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeTo = _feeTo;
    }

    // установка адреса того, кто может устанавливать комиссию для протокола
    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}
