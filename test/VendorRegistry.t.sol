
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {vendorRegistry} from "../src/VendorRegistry.sol";

// Mock with the same functions VendorRegistry calls.
contract MockTimelockForRegistry {
    bytes public lastPayload;
    uint256 public lastDelay;
    bytes32 public lastOperationId;

    function getOpId(bytes memory encodedData)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(encodedData, "salt"));
    }

    function schedule(bytes memory encodedData, uint256 delay)
        public
        returns (uint256 operationEta, bytes32 operationId)
    {
        lastPayload = encodedData;
        lastDelay = delay;
        operationId = getOpId(encodedData);
        lastOperationId = operationId;
        operationEta = block.timestamp + delay;
    }
}

contract VendorRegistryTest is Test {
    vendorRegistry registry;
    MockTimelockForRegistry mockTimelock;

    address proposer = makeAddr("proposer");
    address vendor = makeAddr("vendor");
    address outsider = makeAddr("outsider");

    function setUp() public {
        mockTimelock = new MockTimelockForRegistry();

        registry = new vendorRegistry(
            address(mockTimelock),
            proposer
        );
    }

    // 1. Only the proposer should be able to register a vendor.
    function testOnlyProposerCanRegister() public {
        vm.prank(outsider);
        vm.expectRevert("You do not have access");

        registry.register(vendor, "Vendor One");
    }

    // 2. Registering should schedule a 48-hour operation.
    function testRegisterSchedulesOperation() public {
        vm.prank(proposer);
        registry.register(vendor, "Vendor One");

        assertEq(mockTimelock.lastDelay(), 48 hours);
        assertTrue(mockTimelock.lastOperationId() != bytes32(0));
    }

    // 3. The encoded payload should target this VendorRegistry.
    function testRegisterEncodesRegistryAsTarget() public {
        vm.prank(proposer);
        registry.register(vendor, "Vendor One");

        (address target, bytes memory callData) =
            abi.decode(mockTimelock.lastPayload(), (address, bytes));

        assertEq(target, address(registry));

        (address decodedVendor, string memory decodedName) =
            _decodeExecuteCall(callData);

        assertEq(decodedVendor, vendor);
        assertEq(decodedName, "Vendor One");
    }

    // 4. A vendor with a pending registration cannot be registered again.
    function testCannotRegisterSamePendingVendorTwice() public {
        vm.startPrank(proposer);

        registry.register(vendor, "Vendor One");

        vm.expectRevert(
            "This vendor already exists cannot register again"
        );
        registry.register(vendor, "Vendor One");

        vm.stopPrank();
    }

    // 5. Only the Timelock should be able to execute registration.
    function testOnlyTimelockCanExecute() public {
        vm.prank(outsider);
        vm.expectRevert("Only timelock can call this function");

        registry.execute(vendor, "Vendor One");
    }

    // 6. Execution through the Timelock address should emit vendorAdded.
    function testTimelockCanExecuteRegistration() public {
        vm.expectEmit(true, false, false, true, address(registry));
        emit vendorRegistry.vendorAdded("Vendor One", vendor);

        vm.prank(address(mockTimelock));
        registry.execute(vendor, "Vendor One");
    }

    // 7. A second execution for the same vendor should revert.
    function testCannotExecuteRegistrationTwice() public {
        vm.prank(address(mockTimelock));
        registry.execute(vendor, "Vendor One");

        vm.prank(address(mockTimelock));
        vm.expectRevert("Vendor already registered");
        registry.execute(vendor, "Vendor One");
    }

    // Helper to decode the function selector and arguments.
    function _decodeExecuteCall(bytes memory callData)
        internal
        pure
        returns (address decodedVendor, string memory decodedName)
    {
        bytes4 selector;

        assembly {
            selector := mload(add(callData, 32))
        }

        assertEq(
            selector,
            vendorRegistry.execute.selector
        );

        (decodedVendor, decodedName) = abi.decode(
            _slice(callData, 4),
            (address, string)
        );
    }

    // Removes the first four bytes (function selector).
    function _slice(bytes memory data, uint256 start)
        internal
        pure
        returns (bytes memory result)
    {
        require(start <= data.length);

        result = new bytes(data.length - start);

        for (uint256 i = 0; i < result.length; i++) {
            result[i] = data[i + start];
        }
    }
}
