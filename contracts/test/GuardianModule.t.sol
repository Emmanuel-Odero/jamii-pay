// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {GuardianModule} from "../src/GuardianModule.sol";

contract GuardianModuleTest is Test {
    GuardianModule internal module;
    address internal account = address(0xA11CE);

    uint256 internal ownerKey = 0x01123;
    uint256 internal guardian1Key = 0xA1;
    uint256 internal guardian2Key = 0xA2;
    uint256 internal guardian3Key = 0xA3;
    address internal owner;
    address[] internal guardians;

    function setUp() public {
        module = new GuardianModule();
        owner = vm.addr(ownerKey);
        guardians = new address[](3);
        guardians[0] = vm.addr(guardian1Key);
        guardians[1] = vm.addr(guardian2Key);
        guardians[2] = vm.addr(guardian3Key);
    }

    function _install(uint256 threshold) internal {
        vm.prank(account);
        module.onInstall(abi.encode(owner, guardians, threshold));
    }

    function _sig(uint256 key, bytes32 hash) internal pure returns (bytes memory) {
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, ethHash);
        return abi.encodePacked(r, s, v);
    }

    function test_isModuleType_validator() public view {
        assertTrue(module.isModuleType(1));
    }

    function test_onInstall_configuresThreshold() public {
        _install(2);

        assertEq(module.thresholdOf(account), 2);
        assertEq(module.ownerOf(account), owner);
        assertEq(module.guardiansOf(account).length, 3);
    }

    function test_onInstall_revertsWhenThresholdExceedsGuardians() public {
        address[] memory oneGuardian = new address[](1);
        oneGuardian[0] = guardians[0];

        vm.prank(account);
        vm.expectRevert(GuardianModule.ThresholdExceedsGuardianCount.selector);
        module.onInstall(abi.encode(owner, oneGuardian, uint256(2)));
    }

    function test_isValidSignatureWithSender_acceptsOwnerPlusThresholdGuardians() public {
        _install(2);

        bytes32 hash = keccak256("move savings");
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = _sig(guardian1Key, hash);
        sigs[1] = _sig(guardian2Key, hash);
        bytes memory signature = abi.encode(_sig(ownerKey, hash), sigs);

        assertEq(module.isValidSignatureWithSender(account, hash, signature), bytes4(0x1626ba7e));
    }

    function test_isValidSignatureWithSender_rejectsBelowThreshold() public {
        _install(2);

        bytes32 hash = keccak256("move savings");
        // Only one guardian signature, threshold is 2.
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = _sig(guardian1Key, hash);
        bytes memory signature = abi.encode(_sig(ownerKey, hash), sigs);

        assertEq(module.isValidSignatureWithSender(account, hash, signature), bytes4(0xffffffff));
    }

    function test_isValidSignatureWithSender_rejectsDuplicateGuardianSignature() public {
        _install(2);

        bytes32 hash = keccak256("move savings");
        // Same guardian's signature repeated twice — must not count as two
        // distinct guardians meeting the threshold.
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = _sig(guardian1Key, hash);
        sigs[1] = _sig(guardian1Key, hash);
        bytes memory signature = abi.encode(_sig(ownerKey, hash), sigs);

        assertEq(module.isValidSignatureWithSender(account, hash, signature), bytes4(0xffffffff));
    }

    function test_isValidSignatureWithSender_rejectsWrongOwnerSignature() public {
        _install(2);

        bytes32 hash = keccak256("move savings");
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = _sig(guardian1Key, hash);
        sigs[1] = _sig(guardian2Key, hash);
        // Signed by a guardian instead of the real owner.
        bytes memory signature = abi.encode(_sig(guardian3Key, hash), sigs);

        assertEq(module.isValidSignatureWithSender(account, hash, signature), bytes4(0xffffffff));
    }
}
