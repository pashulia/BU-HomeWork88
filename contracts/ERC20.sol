//SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function transfer(address to, uint256 amount) external returns(bool);
    function approve(address spender, uint256 amount) external returns(bool);
    function transferFrom(address from, address to, uint256 amount) external returns(bool);
    
    function name() external view returns(string memory);
    function symbol() external view returns(string memory);
    function decimals() external view returns(uint8);
    function totalSupply() external view returns(uint256);
    function balanceOf(address account) external view returns(uint256);
    function allowance(address owner, address spender) external view returns(uint256);
}

contract MERC20 is IERC20 {
    string _name;
    string _symbol;
    uint256 _totalSupply;
    uint8 _decimals;
    address _owner;
    

    mapping(address => uint256) balances;
    mapping(address => mapping(address => uint256)) allowed;

    constructor (string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _owner = msg.sender;
    }

    function mint(address to, uint256 amount) public returns(bool) {
        require(_owner == msg.sender, "ERC20: You are not owner!");
        balances[to] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), to, amount);
        return true;
    }

    function burn(uint256 amount) public returns(bool) {
        require(balances[msg.sender] >= amount, "ERC20: Not enough tokens!");
        balances[msg.sender] -= amount;
        _totalSupply -= amount;
        emit Transfer(msg.sender, address(0), amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addValue) public returns(bool) {
        // require(allowed[msg.sender][spender] + addValue > allowed[msg.sender][spender]); для более раних версий
        allowed[msg.sender][spender] += addValue;
        emit Approval(msg.sender, spender, allowed[msg.sender][spender]);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subValue) public returns(bool) {
        allowed[msg.sender][spender] -= subValue;
        emit Approval(msg.sender, spender, allowed[msg.sender][spender]);
        return true;
    }
    
    function transfer(address to, uint256 amount) external returns(bool) {
        require(balances[msg.sender] >= amount, "ERC20: Not enough tokens!");
        balances[msg.sender] -= amount;
        balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns(bool) {
        allowed[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns(bool) {
        require(balances[from] >= amount, "ERC20: Not enough tokens!");
        require(allowed[from][msg.sender] >= amount, "ERC20: Not enough allowed!");
        balances[from] -= amount;
        balances[to] += amount;
        allowed[from][msg.sender] -= amount;
        emit Transfer(from, to, amount);
        emit Approval(from, msg.sender, allowed[from][msg.sender]);
        return true;
    }

    function name() external view returns(string memory) {
        return _name;
    }

    function symbol() external view returns(string memory) {
        return _symbol;
    }

    function decimals() external view returns(uint8) {
        return _decimals;
    }

    function totalSupply() external view returns(uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns(uint256) {
        return balances[account];
    }

    function allowance(address owner, address spender) external view returns(uint256) {
        return allowed[owner][spender];
    }
}
