// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {SpendModule} from "../src/SpendModule.sol";

contract SpendModuleTest is Test {
    SpendModule internal module;
    address internal account = address(0xA11CE);
    address internal pinSigner = address(0xB0B);

    // A real keypair (not just a bare address) — needed to actually
    // produce a signature for validateUserOp/isValidSignatureWithSender
    // to recover against, unlike `pinSigner` above which only stands in
    // for the install/uninstall bookkeeping tests.
    uint256 internal signerKey = 0xBEEF;
    address internal signer;

    function setUp() public {
        module = new SpendModule();
        signer = vm.addr(signerKey);
    }

    function test_isModuleType_validator() public view {
        assertTrue(module.isModuleType(1));
        assertFalse(module.isModuleType(2));
    }

    function test_onInstall_configuresSpendCap() public {
        vm.prank(account);
        module.onInstall(abi.encode(pinSigner, 100 ether));

        (address configuredSigner, uint256 cap) = module.policyOf(account);
        assertEq(configuredSigner, pinSigner);
        assertEq(cap, 100 ether);
    }

    function test_onUninstall_clearsPolicy() public {
        vm.startPrank(account);
        module.onInstall(abi.encode(pinSigner, 100 ether));
        module.onUninstall("");
        vm.stopPrank();

        (address configuredSigner, uint256 cap) = module.policyOf(account);
        assertEq(configuredSigner, address(0));
        assertEq(cap, 0);
    }

    function _sign(bytes32 hash) internal view returns (bytes memory) {
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, ethSignedHash);
        return abi.encodePacked(r, s, v);
    }

    function test_isValidSignatureWithSender_acceptsCorrectSigner() public {
        vm.prank(account);
        module.onInstall(abi.encode(signer, 100 ether));

        bytes32 hash = keccak256("approve this spend");
        bytes4 result = module.isValidSignatureWithSender(account, hash, _sign(hash));
        assertEq(result, bytes4(0x1626ba7e));
    }

    function test_isValidSignatureWithSender_rejectsWrongSigner() public {
        vm.prank(account);
        module.onInstall(abi.encode(signer, 100 ether));

        bytes32 hash = keccak256("approve this spend");
        // Signed with a *different* key than the one configured for
        // `account` — must be rejected, not accepted.
        uint256 wrongKey = 0xDEAD;
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, ethSignedHash);
        bytes4 result = module.isValidSignatureWithSender(account, hash, abi.encodePacked(r, s, v));
        assertEq(result, bytes4(0xffffffff));
    }

    function test_isValidSignatureWithSender_rejectsWhenNotInstalled() public view {
        bytes32 hash = keccak256("approve this spend");
        bytes4 result = module.isValidSignatureWithSender(account, hash, _sign(hash));
        assertEq(result, bytes4(0xffffffff));
    }
}
