//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    constructor() ERC20("TOKEN", "TKN") {
        _mint(msg.sender, 10000 * 10 ** decimals());
    }
}
