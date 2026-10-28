// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IValidator, MODULE_TYPE_VALIDATOR, VALIDATION_SUCCESS, VALIDATION_FAILED} from "erc7579/interfaces/IERC7579Module.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title RecoveryModule
/// @notice Guardian-based social recovery, installed as an ERC-7579
/// validator module on each JamiiPay smart account. Threshold guardian
/// signatures (2-of-3 in the product's default config) queue a *pending*
/// recovery — replacing the account's owner — that only actually takes
/// effect after a 48-hour timelock, giving the real owner (or any guardian,
/// in case the request itself is the attack) a window to cancel it. No
/// owner signature is required to *start* recovery — that's the entire
/// point, the owner is who's unreachable — but the 48h delay plus
/// `cancelRecovery` being callable by the owner is what keeps a stolen
/// guardian majority from being an instant account takeover.
///
/// Same posture as `GuardianModule`: guardians are plain addresses, N-of-M
/// verification built entirely on OpenZeppelin's audited `ECDSA.recover` —
/// no novel cryptographic commitment scheme invented here. See
/// `contracts/README.md`.
contract RecoveryModule is IValidator {
    uint256 public constant TIMELOCK = 48 hours;

    struct RecoveryConfig {
        address owner;
        address[] guardians;
        uint256 threshold;
    }

    struct PendingRecovery {
        address newOwner;
        uint256 readyAt;
    }

    mapping(address account => RecoveryConfig config) private _configs;
    mapping(address account => PendingRecovery pending) private _pending;

    event GuardiansConfigured(address indexed account, address owner, address[] guardians, uint256 threshold);
    event RecoveryStarted(address indexed account, address indexed newOwner, uint256 readyAt);
    event RecoveryCancelled(address indexed account);
    event RecoveryExecuted(address indexed account, address indexed newOwner);

    error ThresholdExceedsGuardianCount();
    error NoPendingRecovery();
    error TimelockNotElapsed(uint256 readyAt);
    error NotOwnerOrGuardian();
    error InsufficientGuardianSignatures();

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

        _configs[msg.sender] = RecoveryConfig({owner: owner, guardians: guardians, threshold: threshold});
        emit GuardiansConfigured(msg.sender, owner, guardians, threshold);
    }

    function onUninstall(bytes calldata) external {
        if (!isInitialized(msg.sender)) revert NotInitialized(msg.sender);
        delete _configs[msg.sender];
        delete _pending[msg.sender];
    }

    /// @dev Starts the 48h recovery timelock for `msg.sender` (the smart
    /// account itself calls this, so `account` is implicit — matches
    /// `onInstall`/`onUninstall`'s pattern of trusting `msg.sender`, not a
    /// passed-in address, as "which account"). `guardianSigs` must recover
    /// to at least `threshold` distinct configured guardians signing over
    /// `newOwner` — no owner signature involved, deliberately.
    function initiateRecovery(address newOwner, bytes[] calldata guardianSigs) external {
        RecoveryConfig storage config = _configs[msg.sender];
        if (config.threshold == 0) revert NotInitialized(msg.sender);

        bytes32 hash = MessageHashUtils.toEthSignedMessageHash(keccak256(abi.encode(msg.sender, newOwner)));
        if (!_meetsThreshold(config, hash, guardianSigs)) revert InsufficientGuardianSignatures();

        uint256 readyAt = block.timestamp + TIMELOCK;
        _pending[msg.sender] = PendingRecovery({newOwner: newOwner, readyAt: readyAt});
        emit RecoveryStarted(msg.sender, newOwner, readyAt);
    }

    /// @dev Callable by anyone once the timelock has elapsed — there's
    /// nothing sensitive about *who* triggers the state transition, only
    /// about who could have started or stopped it. Actually applying
    /// `newOwner` to the account (e.g. re-installing `SpendModule`/
    /// `GuardianModule` with a new signer) is the smart account's own
    /// job once it observes `RecoveryExecuted` — this module only tracks
    /// the guardian-consent-plus-timelock state, per the account's
    /// existing "we configure, we don't reimplement account control"
    /// boundary (contracts/README.md).
    function executeRecovery(address account) external returns (address newOwner) {
        PendingRecovery memory pending = _pending[account];
        if (pending.readyAt == 0) revert NoPendingRecovery();
        if (block.timestamp < pending.readyAt) revert TimelockNotElapsed(pending.readyAt);

        newOwner = pending.newOwner;
        delete _pending[account];
        _configs[account].owner = newOwner;
        emit RecoveryExecuted(account, newOwner);
    }

    /// @dev The owner cancelling is the normal "this wasn't me, I'm still
    /// here" case; a guardian cancelling covers the request itself being
    /// the attack (e.g. a guardian's key was compromised and used to
    /// start a bogus recovery — the *other* guardians, seeing the alert,
    /// can stop it without waiting on the (possibly also compromised)
    /// owner).
    function cancelRecovery(address account) external {
        RecoveryConfig storage config = _configs[account];
        if (msg.sender != config.owner && !_isGuardian(config, msg.sender)) revert NotOwnerOrGuardian();
        if (_pending[account].readyAt == 0) revert NoPendingRecovery();

        delete _pending[account];
        emit RecoveryCancelled(account);
    }

    function pendingRecoveryOf(address account) external view returns (address newOwner, uint256 readyAt) {
        PendingRecovery storage pending = _pending[account];
        return (pending.newOwner, pending.readyAt);
    }

    /// @dev This module doesn't gate ordinary UserOps at all — recovery is
    /// only ever triggered via `initiateRecovery`/`executeRecovery` above,
    /// never through the normal ERC-4337 validation path. Always fails
    /// closed rather than being installed as a second, redundant signer
    /// for everyday transactions.
    function validateUserOp(PackedUserOperation calldata, bytes32) external pure returns (uint256) {
        return VALIDATION_FAILED;
    }

    function isValidSignatureWithSender(address, bytes32, bytes calldata) external pure returns (bytes4) {
        return 0xffffffff;
    }

    function _meetsThreshold(RecoveryConfig storage config, bytes32 ethHash, bytes[] calldata guardianSigs)
        internal
        view
        returns (bool)
    {
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

    function _isGuardian(RecoveryConfig storage config, address who) internal view returns (bool) {
        for (uint256 i = 0; i < config.guardians.length; i++) {
            if (config.guardians[i] == who) return true;
        }
        return false;
    }

    function guardiansOf(address account) external view returns (address[] memory) {
        return _configs[account].guardians;
    }

    function ownerOf(address account) external view returns (address) {
        return _configs[account].owner;
    }

    function thresholdOf(address account) external view returns (uint256) {
        return _configs[account].threshold;
    }
}
