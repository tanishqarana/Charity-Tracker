
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Timelock} from "../src/Timelock.sol";

// A target contract that the Timelock can execute.
contract MockTarget {
    uint256 public value;

    function setValue(uint256 _value) external {
        value = _value;
    }

    function alwaysRevert() external pure {
        revert("Target reverted");
    }
}

contract TimelockTest is Test {
    Timelock timelock;
    MockTarget target;

    address proposer = makeAddr("proposer");
    address cancellor = makeAddr("cancellor");
    address executor = makeAddr("executor");
    address outsider = makeAddr("outsider");

    function setUp() public {
        timelock = new Timelock(proposer, cancellor, executor);
        target = new MockTarget();
    }

    // Helper: creates the outer (target, calldata) payload.
    function _encodeSetValue(uint256 _value)
        internal
        view
        returns (bytes memory)
    {
        return abi.encode(
            address(target),
            abi.encodeCall(MockTarget.setValue, (_value))
        );
    }

    // 1. Scheduling should create a Waiting operation.
    function testScheduleCreatesWaitingOperation() public {
        bytes memory payload = _encodeSetValue(100);

        vm.prank(proposer);
        (uint256 operationEta, bytes32 operationId) =
            timelock.schedule(payload, 48 hours);

        assertEq(
            uint256(timelock.checkState(operationId)),
            uint256(Timelock.OperationState.Waiting)
        );

        assertEq(operationEta, block.timestamp + 48 hours);
    }

    // 2. An unscheduled operation should be Unset.
    function testUnscheduledOperationIsUnset() public view {
        bytes32 operationId = keccak256("unknown operation");

        assertEq(
            uint256(timelock.checkState(operationId)),
            uint256(Timelock.OperationState.Unset)
        );
    }

    // 3. An operation should become Ready after its ETA.
    function testOperationBecomesReadyAfterEta() public {
        bytes memory payload = _encodeSetValue(100);

        vm.prank(proposer);
        (uint256 operationEta, bytes32 operationId) =
            timelock.schedule(payload, 48 hours);

        vm.warp(operationEta);

        assertEq(
            uint256(timelock.checkState(operationId)),
            uint256(Timelock.OperationState.Ready)
        );
    }

    // 4. A delay below MIN_DELAY should be bumped to MIN_DELAY.
    function testScheduleEnforcesMinimumDelay() public {
        bytes memory payload = _encodeSetValue(100);

        vm.prank(proposer);
        (uint256 operationEta, ) = timelock.schedule(payload, 1 hours);

        assertEq(operationEta, block.timestamp + timelock.MIN_DELAY());
    }

    // 5. Only the proposer should be able to schedule.
    function testNonProposerCannotSchedule() public {
        bytes memory payload = _encodeSetValue(100);

        vm.prank(outsider);
        vm.expectRevert("Not authorised to run this");
        timelock.schedule(payload, 48 hours);
    }

    // 6. The same payload should not be schedulable twice while queued.
    function testCannotScheduleSameOperationTwice() public {
        bytes memory payload = _encodeSetValue(100);

        vm.prank(proposer);
        timelock.schedule(payload, 48 hours);

        vm.prank(proposer);
        vm.expectRevert("Operation already Scheduled");
        timelock.schedule(payload, 48 hours);
    }

    // 7. Only the executor should be able to execute.
    function testNonExecutorCannotExecute() public {
        bytes memory payload = _encodeSetValue(100);

        vm.prank(proposer);
        (, bytes32 operationId) = timelock.schedule(payload, 48 hours);

        vm.warp(block.timestamp + 48 hours);

        vm.prank(outsider);
        vm.expectRevert("Not authorised to run this");
        timelock.execute(operationId);
    }

    // 8. Execution should call the target and mark the operation Done.
    function testExecuteCallsTargetAndMarksDone() public {
        bytes memory payload = _encodeSetValue(100);

        vm.prank(proposer);
        (uint256 operationEta, bytes32 operationId) =
            timelock.schedule(payload, 48 hours);

        vm.warp(operationEta);

        vm.prank(executor);
        timelock.execute(operationId);

        assertEq(target.value(), 100);

        assertEq(
            uint256(timelock.checkState(operationId)),
            uint256(Timelock.OperationState.Done)
        );
    }

    // 9. An operation cannot be executed before its ETA.
    function testCannotExecuteBeforeEta() public {
        bytes memory payload = _encodeSetValue(100);

        vm.prank(proposer);
        (, bytes32 operationId) = timelock.schedule(payload, 48 hours);

        vm.prank(executor);
        vm.expectRevert(
            "Operation not in Ready, please checkState to ensure state of operation"
        );
        timelock.execute(operationId);
    }

    // 10. A cancelled operation should return to Unset.
    function testCancelResetsOperationToUnset() public {
        bytes memory payload = _encodeSetValue(100);

        vm.prank(proposer);
        (, bytes32 operationId) = timelock.schedule(payload, 48 hours);

        vm.prank(cancellor);
        timelock.cancel(operationId);

        assertEq(
            uint256(timelock.checkState(operationId)),
            uint256(Timelock.OperationState.Unset)
        );
    }

    // 11. Only the cancellor should be able to cancel.
    function testNonCancellorCannotCancel() public {
        bytes memory payload = _encodeSetValue(100);

        vm.prank(proposer);
        (, bytes32 operationId) = timelock.schedule(payload, 48 hours);

        vm.prank(outsider);
        vm.expectRevert("Not authorised to run this");
        timelock.cancel(operationId);
    }

    // 12. A completed operation cannot be cancelled.
    function testCannotCancelCompletedOperation() public {
        bytes memory payload = _encodeSetValue(100);

        vm.prank(proposer);
        (uint256 operationEta, bytes32 operationId) =
            timelock.schedule(payload, 48 hours);

        vm.warp(operationEta);

        vm.prank(executor);
        timelock.execute(operationId);

        vm.prank(cancellor);
        vm.expectRevert(
            abi.encodeWithSelector(
                Timelock.stateDone.selector,
                "Operation already executed, cannot cancel anymore"
            )
        );
        timelock.cancel(operationId);
    }

    // 13. If the target reverts, the operation must not remain Done.
    function testTargetRevertRollsBackDoneState() public {
        bytes memory payload = abi.encode(
            address(target),
            abi.encodeCall(MockTarget.alwaysRevert, ())
        );

        vm.prank(proposer);
        (uint256 operationEta, bytes32 operationId) =
            timelock.schedule(payload, 48 hours);

        vm.warp(operationEta);

        vm.prank(executor);
        vm.expectRevert("Transaction failed");
        timelock.execute(operationId);

        // The entire transaction reverts, including the Done assignment.
        assertEq(
            uint256(timelock.checkState(operationId)),
            uint256(Timelock.OperationState.Ready)
        );
    }

    // 14. A target address without contract code should be rejected.
    function testCannotExecuteAgainstEOA() public {
        address eoa = makeAddr("eoa");

        bytes memory payload = abi.encode(
            eoa,
            abi.encodeWithSignature("someFunction()")
        );

        vm.prank(proposer);
        (uint256 operationEta, bytes32 operationId) =
            timelock.schedule(payload, 48 hours);

        vm.warp(operationEta);

        vm.prank(executor);
        vm.expectRevert("Target is not a contract");
        timelock.execute(operationId);
    }
}
