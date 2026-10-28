// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IValidator, MODULE_TYPE_VALIDATOR, VALIDATION_SUCCESS, VALIDATION_FAILED} from "erc7579/interfaces/IERC7579Module.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title ServerCosignModule
/// @notice Validator for savings/high-value moves: authorizes a transfer
/// only with the account owner's own signature *plus* the JamiiPay
/// server co-signer over the same hash. The server signs only after its
/// off-chain release/policy checks pass (wallet-PIN proof, throttle,
/// audit log, guardian alerts — see `crates/server/src/routes/backups.rs`).
/// A raw device key alone — phished, brute-forced out of a backup, or
/// wielded under coercion — can never move savings without the server's
/// independent approval, and the server alone can never move anything
/// without the owner's signature. Compromise of either side alone is
/// insufficient; that is the whole point.
///
/// Same posture as `GuardianModule`: plain addresses, N-of-2 verification
/// built entirely on OpenZeppelin's audited `ECDSA.recover` — no novel
/// cryptography invented here. The server key rotates via
/// `rotateServerSigner`, callable only by the account itself (i.e. through
/// a UserOp the current validators already approved), so a leaked server
/// key is recoverable without redeploying the account.
contract ServerCosignModule is IValidator {
    struct CosignConfig {
        address owner;
        address serverSigner;
    }

    mapping(address account => CosignConfig config) private _configs;

    event ServerCosignConfigured(address indexed account, address owner, address serverSigner);
    event ServerSignerRotated(address indexed account, address oldSigner, address newSigner);

    error NotConfigured(address account);
    error ZeroAddress();

    function isModuleType(uint256 typeID) external pure returns (bool) {
        return typeID == MODULE_TYPE_VALIDATOR;
    }

    function isInitialized(address smartAccount) public view returns (bool) {
        return _configs[smartAccount].serverSigner != address(0);
    }

    function onInstall(bytes calldata data) external {
        if (isInitialized(msg.sender)) revert AlreadyInitialized(msg.sender);
        (address owner, address serverSigner) = abi.decode(data, (address, address));
        if (owner == address(0) || serverSigner == address(0)) revert ZeroAddress();
        _configs[msg.sender] = CosignConfig({owner: owner, serverSigner: serverSigner});
        emit ServerCosignConfigured(msg.sender, owner, serverSigner);
    }

    function onUninstall(bytes calldata) external {
        if (!isInitialized(msg.sender)) revert NotInitialized(msg.sender);
        delete _configs[msg.sender];
    }

    /// @dev Rotates the server co-signer. Callable only by the account
    /// itself — in practice that means through execution the current
    /// owner+server pair already authorized, so neither side can lock the
    /// other out unilaterally... unless they collude, in which case the
    /// funds were already movable. RecoveryModule remains the backstop for
    /// a truly dead server key (guardians replace the owner set, then
    /// reinstall this module with the new signer).
    function rotateServerSigner(address newSigner) external {
        CosignConfig storage config = _configs[msg.sender];
        if (config.serverSigner == address(0)) revert NotConfigured(msg.sender);
        if (newSigner == address(0)) revert ZeroAddress();
        address old = config.serverSigner;
        config.serverSigner = newSigner;
        emit ServerSignerRotated(msg.sender, old, newSigner);
    }

    /// @dev Called by the account during the ERC-4337 validation phase.
    /// Never reverts on a failed check — bundler simulation requires a
    /// clean success/fail return, same as `GuardianModule.validateUserOp`.
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

    /// @dev `signature` is `abi.encode(ownerSignature, serverSignature)` —
    /// both plain ECDSA signatures over the same `hash`. Either side
    /// missing or wrong fails closed.
    function _verify(address account, bytes32 hash, bytes calldata signature) internal view returns (bool) {
        CosignConfig storage config = _configs[account];
        if (config.serverSigner == address(0)) return false;

        (bytes memory ownerSig, bytes memory serverSig) = abi.decode(signature, (bytes, bytes));

        bytes32 ethHash = MessageHashUtils.toEthSignedMessageHash(hash);
        (address ownerRecovered, ECDSA.RecoverError ownerErr,) = ECDSA.tryRecover(ethHash, ownerSig);
        if (ownerErr != ECDSA.RecoverError.NoError || ownerRecovered != config.owner) return false;
        (address serverRecovered, ECDSA.RecoverError serverErr,) = ECDSA.tryRecover(ethHash, serverSig);
        if (serverErr != ECDSA.RecoverError.NoError || serverRecovered != config.serverSigner) return false;
        return true;
    }

    function ownerOf(address account) external view returns (address) {
        return _configs[account].owner;
    }

    function serverSignerOf(address account) external view returns (address) {
        return _configs[account].serverSigner;
    }
}
