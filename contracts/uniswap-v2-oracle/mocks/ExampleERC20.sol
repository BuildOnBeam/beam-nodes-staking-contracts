// (c) 2023, Ava Labs, Inc. All rights reserved.
// See the file LICENSE for licensing terms.

// SPDX-License-Identifier: Ecosystem

pragma solidity ^0.8.25;

/**
 * THIS IS AN EXAMPLE CONTRACT THAT USES UN-AUDITED CODE.
 * DO NOT USE THIS CODE IN PRODUCTION.
 */
import {
    ERC20Burnable, ERC20
} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract ExampleERC20 is ERC20Burnable {
    string private constant _TOKEN_NAME = "Mock Token";
    string private constant _TOKEN_SYMBOL = "MOCK";

    constructor() ERC20(_TOKEN_NAME, _TOKEN_SYMBOL) {
        _mint(msg.sender, 1e28);
    }

    function mint(
        uint256 amount
    ) external {
        _mint(msg.sender, amount);
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}
