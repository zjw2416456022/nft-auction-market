// contracts/MockUSDC.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title 仅用于本地和测试网的 Mock USDC
 *dev 18 位小数，和真实 USDC 在主网不一样，但测试够用
 */
contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {
        // 给自己铸 100 万枚，方便测试发币
        _mint(msg.sender, 1_000_000 * 10**18);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    // 覆盖 decimals，真实 USDC 是 6 位，但我们这里用 18 位更方便计算
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }
}