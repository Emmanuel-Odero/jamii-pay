// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IValidator, MODULE_TYPE_VALIDATOR, VALIDATION_SUCCESS, VALIDATION_FAILED} from "erc7579/interfaces/IERC7579Module.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title GuardianModule
/// @notice Validator for savings: authorizes a transfer only with the
/// account owner's own signature *plus* a threshold (2-of-3, in the
/// product's default config) of guardian co-signatures. Per the tech deck,
/// this is "enforced on-chain, not just in the app's UI" — even a fully
/// compromised app session or a phone unlocked under coercion cannot move
/// savings without the guardian threshold.
///
/// Distinct from `RecoveryModule`: this module gates ordinary savings
/// transfers (no timelock, needs the current owner's signature too);
/// `RecoveryModule` gates *replacing* the owner/signers entirely when the
/// owner is unreachable (has a timelock, doesn't need the old owner's
/// signature — that's the point of recovery).
///
/// Guardian identities are stored as plain addresses, not hidden behind a
/// salted-hash commitment — a genuine privacy-preserving guardian scheme is
/// real cryptographic protocol design (how the salt is generated/shared,
/// how a signature is matched to a commitment without revealing identity)
/// that shouldn't be invented ad hoc for money-moving logic; this is the
/// well-understood N-of-M multisig pattern instead, built entirely on
/// OpenZeppelin's audited `ECDSA.recover` — see `contracts/README.md`.
contract GuardianModule is IValidator {
    struct GuardianConfig {
        address owner;
        address[] guardians;
        uint256 threshold;
    }

    mapping(address account => GuardianConfig config) private _configs;

    event GuardianConfigured(address indexed account, address owner, uint256 guardianCount, uint256 threshold);

    error ThresholdExceedsGuardianCount();

    function isModuleType(uint256 typeID) external pure returns (bool) {
        return typeID == MODULE_TYPE_VALIDATOR;
    }

    function isInitialized(address smartAccount) public view returns (bool) {
        return _configs[smartAccount].threshold != 0;
    }

    function onInstall(bytes calldata data) external {
        if (isInitialized(msg.sender)) revert AlreadyInitialized(msg.sender);
        (address owner, address[] memory guardians, uint256 threshold) =
            abi.decode(data, (address, address[], uint256));
        if (threshold == 0 || threshold > guardians.length) revert ThresholdExceedsGuardianCount();

        _configs[msg.sender] = GuardianConfig({owner: owner, guardians: guardians, threshold: threshold});
        emit GuardianConfigured(msg.sender, owner, guardians.length, threshold);
    }

    function onUninstall(bytes calldata) external {
        if (!isInitialized(msg.sender)) revert NotInitialized(msg.sender);
        delete _configs[msg.sender];
    }

    /// @dev Called by the account during the ERC-4337 validation phase.
    /// Never reverts on a failed check — see `SpendModule.validateUserOp`'s
    /// doc comment for why that matters to bundler simulation.
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash)
        external
        view
        returns (uint256)
    {
        return _verify(userOp.sender, userOpHash, userOp.signature) ? VALIDATION_SUCCESS : VALIDATION_FAILED;
    }

    function isValidSignatureWithSender(address sender, bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4)
    {
        return _verify(sender, hash, signature) ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }

    /// @dev `signature` is `abi.encode(ownerSignature, guardianSignatures)`
    /// — the owner's own ECDSA signature over `hash`, plus an array of
    /// guardian signatures over the same `hash` (any order, any subset —
    /// only `threshold` of them need to actually recover to a configured
    /// guardian; extras are simply ignored once the threshold is met).
    /// Each guardian can only be counted once even if their signature
    /// appears more than once in the array, so duplicating one guardian's
    /// signature can never substitute for real distinct threshold consent.
    function _verify(address account, bytes32 hash, bytes calldata signature) internal view returns (bool) {
        GuardianConfig storage config = _configs[account];
        if (config.threshold == 0) return false;

        (bytes memory ownerSig, bytes[] memory guardianSigs) = abi.decode(signature, (bytes, bytes[]));

        bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(hash);
        (address ownerRecovered, ECDSA.RecoverError ownerErr,) = ECDSA.tryRecover(ethHash, ownerSig);
        if (ownerErr != ECDSA.RecoverError.NoError || ownerRecovered != config.owner) return false;

        uint256 guardianCount = config.guardians.length;
        bool[] memory used = new bool[](guardianCount);
        uint256 matched = 0;

        for (uint256 i = 0; i < guardianSigs.length && matched < config.threshold; i++) {
            (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(ethHash, guardianSigs[i]);
            if (err != ECDSA.RecoverError.NoError) continue;
            for (uint256 j = 0; j < guardianCount; j++) {
                if (!used[j] && config.guardians[j] == recovered) {
                    used[j] = true;
                    matched++;
                    break;
                }
            }
        }

        return matched >= config.threshold;
    }

    function ownerOf(address account) external view returns (address) {
        return _configs[account].owner;
    }

    function thresholdOf(address account) external view returns (uint256) {
        return _configs[account].threshold;
    }

    function guardiansOf(address account) external view returns (address[] memory) {
        return _configs[account].guardians;
    }
}
