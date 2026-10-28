// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {RecoveryModule} from "../src/RecoveryModule.sol";

contract RecoveryModuleTest is Test {
    RecoveryModule internal module;
    address internal account = address(0xA11CE);

    address internal owner = address(0xDEAD);
    uint256 internal guardian1Key = 0xA1;
    uint256 internal guardian2Key = 0xA2;
    uint256 internal guardian3Key = 0xA3;
    address[] internal guardians;

    function setUp() public {
        module = new RecoveryModule();
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
        assertFalse(module.isModuleType(2));
    }

    function test_onInstall_configuresGuardians() public {
        _install(2);

        assertEq(module.thresholdOf(account), 2);
        assertEq(module.ownerOf(account), owner);
        assertEq(module.guardiansOf(account).length, 3);
    }

    function test_onInstall_revertsWhenThresholdExceedsGuardians() public {
        address[] memory oneGuardian = new address[](1);
        oneGuardian[0] = guardians[0];

        vm.prank(account);
        vm.expectRevert(RecoveryModule.ThresholdExceedsGuardianCount.selector);
        module.onInstall(abi.encode(owner, oneGuardian, uint256(2)));
    }

    function _startRecovery(address newOwner) internal {
        bytes32 hash = keccak256(abi.encode(account, newOwner));
        bytes[] memory sigs = new bytes[](2);
        sigs[0] = _sig(guardian1Key, hash);
        sigs[1] = _sig(guardian2Key, hash);

        vm.prank(account);
        module.initiateRecovery(newOwner, sigs);
    }

    function test_initiateRecovery_queuesWithTimelock() public {
        _install(2);
        address newOwner = address(0xB0B);

        _startRecovery(newOwner);

        (address pendingOwner, uint256 readyAt) = module.pendingRecoveryOf(account);
        assertEq(pendingOwner, newOwner);
        assertEq(readyAt, block.timestamp + module.TIMELOCK());
    }

    function test_initiateRecovery_revertsBelowThreshold() public {
        _install(2);
        address newOwner = address(0xB0B);
        bytes32 hash = keccak256(abi.encode(account, newOwner));
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = _sig(guardian1Key, hash);

        vm.prank(account);
        vm.expectRevert(RecoveryModule.InsufficientGuardianSignatures.selector);
        module.initiateRecovery(newOwner, sigs);
    }

    function test_executeRecovery_revertsBeforeTimelockElapses() public {
        _install(2);
        address newOwner = address(0xB0B);
        _startRecovery(newOwner);

        (, uint256 readyAt) = module.pendingRecoveryOf(account);
        vm.expectRevert(abi.encodeWithSelector(RecoveryModule.TimelockNotElapsed.selector, readyAt));
        module.executeRecovery(account);
    }

    function test_executeRecovery_succeedsAfterTimelock() public {
        _install(2);
        address newOwner = address(0xB0B);
        _startRecovery(newOwner);

        vm.warp(block.timestamp + module.TIMELOCK());
        address returnedOwner = module.executeRecovery(account);

        assertEq(returnedOwner, newOwner);
        assertEq(module.ownerOf(account), newOwner);
        (address pendingOwner, uint256 readyAt) = module.pendingRecoveryOf(account);
        assertEq(pendingOwner, address(0));
        assertEq(readyAt, 0);
    }

    function test_cancelRecovery_byOwner_clearsPending() public {
        _install(2);
        _startRecovery(address(0xB0B));

        vm.prank(owner);
        module.cancelRecovery(account);

        (, uint256 readyAt) = module.pendingRecoveryOf(account);
        assertEq(readyAt, 0);
    }

    function test_cancelRecovery_byGuardian_clearsPending() public {
        _install(2);
        _startRecovery(address(0xB0B));

        vm.prank(guardians[2]);
        module.cancelRecovery(account);

        (, uint256 readyAt) = module.pendingRecoveryOf(account);
        assertEq(readyAt, 0);
    }

    function test_cancelRecovery_revertsForUnrelatedCaller() public {
        _install(2);
        _startRecovery(address(0xB0B));

        vm.prank(address(0x999999));
        vm.expectRevert(RecoveryModule.NotOwnerOrGuardian.selector);
        module.cancelRecovery(account);
    }

    function test_validateUserOp_alwaysFails() public view {
        // RecoveryModule never gates ordinary UserOps — recovery only
        // happens via initiateRecovery/executeRecovery.
        assertEq(module.isValidSignatureWithSender(account, bytes32(0), ""), bytes4(0xffffffff));
    }
}
