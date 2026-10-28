// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ServerCosignModule} from "../src/ServerCosignModule.sol";

contract ServerCosignModuleTest is Test {
    ServerCosignModule internal module;
    address internal account = address(0xA11CE);

    uint256 internal ownerKey = 0x01123;
    uint256 internal serverKey = 0xBEEF;
    uint256 internal strangerKey = 0xDEAD;
    address internal owner;
    address internal serverSigner;

    function setUp() public {
        module = new ServerCosignModule();
        owner = vm.addr(ownerKey);
        serverSigner = vm.addr(serverKey);
    }

    function _install() internal {
        vm.prank(account);
        module.onInstall(abi.encode(owner, serverSigner));
    }

    function _sig(uint256 key, bytes32 hash) internal pure returns (bytes memory) {
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, ethHash);
        return abi.encodePacked(r, s, v);
    }

    function test_isModuleType_validator() public view {
        assertTrue(module.isModuleType(1));
    }

    function test_onInstall_configuresOwnerAndServer() public {
        _install();

        assertEq(module.ownerOf(account), owner);
        assertEq(module.serverSignerOf(account), serverSigner);
    }

    function test_isValidSignatureWithSender_acceptsBothSignatures() public {
        _install();
        bytes32 hash = keccak256("move savings");
        bytes memory sig = abi.encode(_sig(ownerKey, hash), _sig(serverKey, hash));

        assertEq(
            module.isValidSignatureWithSender(account, hash, sig),
            bytes4(0x1626ba7e)
        );
    }

    function test_isValidSignatureWithSender_rejectsOwnerOnly() public {
        _install();
        bytes32 hash = keccak256("move savings");
        bytes memory sig = abi.encode(_sig(ownerKey, hash), _sig(strangerKey, hash));

        assertEq(
            module.isValidSignatureWithSender(account, hash, sig),
            bytes4(0xffffffff)
        );
    }

    function test_isValidSignatureWithSender_rejectsServerOnly() public {
        _install();
        bytes32 hash = keccak256("move savings");
        bytes memory sig = abi.encode(_sig(strangerKey, hash), _sig(serverKey, hash));

        assertEq(
            module.isValidSignatureWithSender(account, hash, sig),
            bytes4(0xffffffff)
        );
    }

    function test_rotateServerSigner_onlyAccount() public {
        _install();
        address rotated = vm.addr(0xCAFE);

        // Stranger cannot rotate.
        vm.prank(address(0xBAD));
        vm.expectRevert(
            abi.encodeWithSelector(ServerCosignModule.NotConfigured.selector, address(0xBAD))
        );
        module.rotateServerSigner(rotated);

        // The account itself can.
        vm.prank(account);
        module.rotateServerSigner(rotated);
        assertEq(module.serverSignerOf(account), rotated);
    }
}
