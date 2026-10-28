// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

/// @notice Minimal subset of the ERC-7579 module interface this repo relies
/// on directly. The full standard interfaces ship with the vendored
/// `erc7579-implementation` library (see remappings.txt) — this file exists
/// only so JamiiPay's own contracts compile before that dependency is
/// installed, and to document exactly which module types we consume.
interface IERC7579Module {
    /// Module type IDs per ERC-7579.
    // 1 = validator, 2 = executor, 3 = fallback, 4 = hook
    function isModuleType(uint256 typeID) external view returns (bool);

    function onInstall(bytes calldata data) external;

    function onUninstall(bytes calldata data) external;
}

interface IERC7579Validator is IERC7579Module {
    function isValidSignatureWithSender(address sender, bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4);
}
