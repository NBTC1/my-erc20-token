// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract NBTC is ERC20 {
    address public constant LIQUIDITY_ADDRESS = 0xF113275FECc41f396603B677df15eCd1B4A966DB; // 替换为您的地址

    constructor() ERC20("NanoBitcoin", "NBTC") {
        _mint(address(this), 21_000_000 * 10**18); // 总供应量：21,000,000 NBTC
        _transfer(address(this), LIQUIDITY_ADDRESS, 2_280 * 10**18); // 剩余 2,280 NBTC 到您的地址
        // 剩余 20,997,720 NBTC 留在合约地址，用于 FairDistribution
    }
}