// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IValidator, MODULE_TYPE_VALIDATOR, VALIDATION_SUCCESS, VALIDATION_FAILED} from "erc7579/interfaces/IERC7579Module.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title SpendModule
/// @notice Validator for the "everyday" balance: a single PIN-derived
/// signature authorizes a transfer, but only up to a per-account spend cap.
/// This is deliberately the *only* thing reachable under duress — per the
/// tech deck, "the only thing reachable under duress" by design, so it
/// carries no guardian requirement and no timelock. `GuardianModule` is the
/// separate, stricter validator installed for savings.
///
/// Signature verification uses OpenZeppelin's audited `ECDSA` library
/// (`ecrecover`, wrapped to reject malleable signatures and the zero
/// address) rather than anything hand-rolled — see the parent
/// `contracts/README.md`'s stated boundary: this repo configures audited
/// primitives, it doesn't write new cryptography.
///
/// Per-period spend-cap *accounting* (tracking cumulative spend against
/// `everydayCapWei` within a window) is still a follow-up — `everydayCapWei`
/// is stored and returned by `policyOf`, but nothing here enforces it yet.
/// A validator can only approve/reject a signature; enforcing a rolling cap
/// needs either an ERC-7579 hook (checking cumulative spend before
/// execution) or cap logic inside the account's executor, not something
/// that belongs bolted onto signature verification itself.
contract SpendModule is IValidator {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    struct SpendPolicy {
        /// Signer derived from the account owner's PIN (see the tech deck:
        /// "A PIN unlocks... signers: { passkey, pinDerivedKey }"). Stored
        /// as an address recovered from that key's signature, not the key
        /// itself.
        address pinDerivedSigner;
        uint256 everydayCapWei;
    }

    mapping(address account => SpendPolicy policy) private _policies;

    event SpendPolicyConfigured(address indexed account, address pinDerivedSigner, uint256 everydayCapWei);

    function isModuleType(uint256 typeID) external pure returns (bool) {
        return typeID == MODULE_TYPE_VALIDATOR;
    }

    function isInitialized(address smartAccount) public view returns (bool) {
        return _policies[smartAccount].pinDerivedSigner != address(0);
    }

    function onInstall(bytes calldata data) external {
        if (isInitialized(msg.sender)) revert AlreadyInitialized(msg.sender);
        (address pinDerivedSigner, uint256 everydayCapWei) = abi.decode(data, (address, uint256));
        _policies[msg.sender] = SpendPolicy({pinDerivedSigner: pinDerivedSigner, everydayCapWei: everydayCapWei});
        emit SpendPolicyConfigured(msg.sender, pinDerivedSigner, everydayCapWei);
    }

    function onUninstall(bytes calldata) external {
        if (!isInitialized(msg.sender)) revert NotInitialized(msg.sender);
        delete _policies[msg.sender];
    }

    /// @dev Called by the account (via EntryPoint) during the ERC-4337
    /// validation phase. MUST NOT revert on a bad signature — ERC-4337
    /// requires returning `VALIDATION_FAILED` so bundler simulation can
    /// distinguish "this UserOp is invalid" from "the validator itself is
    /// broken". Reverting here (the previous behaviour) broke that
    /// contract entirely.
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash)
        external
        view
        returns (uint256)
    {
        address signer = _policies[userOp.sender].pinDerivedSigner;
        if (signer == address(0)) return VALIDATION_FAILED;

        address recovered = userOpHash.toEthSignedMessageHash().recover(userOp.signature);
        return recovered == signer ? VALIDATION_SUCCESS : VALIDATION_FAILED;
    }

    /// @dev ERC-1271 passthrough — lets off-chain/dApp signature checks
    /// (not just EntryPoint UserOps) validate against the same
    /// PIN-derived signer. Returns the ERC-1271 magic value on success,
    /// `0xffffffff` on failure — same "never revert" contract as
    /// `validateUserOp`, ERC-1271 callers expect a value back, not a
    /// revert, to distinguish "invalid" from "this contract is broken".
    function isValidSignatureWithSender(address sender, bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4)
    {
        address signer = _policies[sender].pinDerivedSigner;
        if (signer == address(0)) return 0xffffffff;

        address recovered = hash.toEthSignedMessageHash().recover(signature);
        return recovered == signer ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }

    function policyOf(address account) external view returns (address signer, uint256 capWei) {
        SpendPolicy storage policy = _policies[account];
        return (policy.pinDerivedSigner, policy.everydayCapWei);
    }
}
