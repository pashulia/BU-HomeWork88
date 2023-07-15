//SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

interface iUni {
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
}

contract CallUni {
    function call(address pair, uint amount0Out, uint amount1Out, address to, bytes calldata data) public {
        iUni(pair).swap(amount0Out, amount1Out, address to, bytes calldata data)
    }
}
