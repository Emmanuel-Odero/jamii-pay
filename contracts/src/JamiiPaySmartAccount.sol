// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

/// @title JamiiPaySmartAccount
/// @notice Configuration surface over an audited ERC-4337/ERC-7579 smart
/// account implementation (kernel/safe-erc7579/etc — see contracts/README.md
/// for the chosen base once selected). This repo does not reimplement
/// account abstraction; it wires JamiiPay's chosen validator/executor/
/// recovery modules into that base at deploy time.
///
/// This file is a placeholder documenting the shape of that wiring until an
/// audited base contract is vendored in via `forge install`.
interface IJamiiPaySmartAccountConfig {
    function installValidator(address module, bytes calldata initData) external;
    function installExecutor(address module, bytes calldata initData) external;
    function uninstallModule(uint256 moduleTypeId, address module, bytes calldata deinitData) external;
}
