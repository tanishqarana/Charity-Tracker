
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {CharityDonationTracker} from "../src/Donations.sol";

contract MockUSDC is ERC20 {

    constructor() ERC20("Mock USDC", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract MockVendorRegistry {

    mapping(address => bool) public registeredVendors;

    function registerVendor(address vendor) external {
        registeredVendors[vendor] = true;
    }

    function removeVendor(address vendor) external {
        registeredVendors[vendor] = false;
    }

    function isRegistered(address vendor)
        external
        view
        returns (bool)
    {
        return registeredVendors[vendor];
    }
}

contract CharityDonationTrackerTest is Test {

    CharityDonationTracker tracker;
    MockUSDC usdc;
    MockVendorRegistry registry;

    // Admins
    address admin1 = makeAddr("admin1");
    address admin2 = makeAddr("admin2");
    address admin3 = makeAddr("admin3");

    // Donors
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    // Vendors
    address vendor1 = makeAddr("vendor1");
    address vendor2 = makeAddr("vendor2");

    address outsider = makeAddr("outsider");

    uint256 initialTarget = 3 ether;

    uint256 constant ONE_USDC = 1_000_000;

    function setUp() public {

        usdc = new MockUSDC();

        registry = new MockVendorRegistry();

        tracker = new CharityDonationTracker(
            admin1,
            admin2,
            admin3,
            address(usdc),
            address(registry),
            initialTarget
        );

        registry.registerVendor(vendor1);
        registry.registerVendor(vendor2);

        // Give donors ETH.
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        // Give donors USDC.
        usdc.mint(alice, 1000 * ONE_USDC);
        usdc.mint(bob, 1000 * ONE_USDC);

        // Approve the donation contract to spend USDC.
        vm.prank(alice);
        usdc.approve(address(tracker), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(tracker), type(uint256).max);
    }

    // 1. ETH donation should be recorded.

    function testETHDonation() public {

        vm.prank(alice);
        tracker.donateETH{value: 1 ether}();

        assertEq(
            tracker.totalETHDonated(alice),
            1 ether
        );

        assertEq(
            tracker.totalETHDonations(),
            1 ether
        );

        assertEq(
            tracker.allocatedETH(),
            1 ether
        );

        assertEq(
            tracker.donationCount(alice),
            1
        );

        assertEq(
            address(tracker).balance,
            1 ether
        );
    }

    // 2. USDC donation should be recorded.

    function testUSDCDonation() public {

        vm.prank(alice);
        tracker.donateUSDC(10 * ONE_USDC);

        assertEq(
            tracker.totalUSDCDonated(alice),
            10 * ONE_USDC
        );

        assertEq(
            tracker.totalUSDCDonations(),
            10 * ONE_USDC
        );

        assertEq(
            tracker.allocatedUSDC(),
            10 * ONE_USDC
        );

        assertEq(
            tracker.donationCount(alice),
            1
        );

        assertEq(
            usdc.balanceOf(address(tracker)),
            10 * ONE_USDC
        );
    }

    // 3. Zero ETH donation should revert.

    function testZeroETHDonationReverts() public {

        vm.prank(alice);

        vm.expectRevert("Donation must be greater than zero");

        tracker.donateETH{value: 0}();
    }

    // 4. Zero USDC donation should revert.

    function testZeroUSDCDonationReverts() public {

        vm.prank(alice);

        vm.expectRevert("Donation must be greater than zero");

        tracker.donateUSDC(0);
    }

    // 5. Multiple donations should update cumulative totals.

    function testMultipleDonationsUpdateTotals() public {

        vm.startPrank(alice);

        tracker.donateETH{value: 1 ether}();

        tracker.donateUSDC(10 * ONE_USDC);

        tracker.donateETH{value: 2 ether}();

        vm.stopPrank();

        assertEq(
            tracker.totalETHDonated(alice),
            3 ether
        );

        assertEq(
            tracker.totalUSDCDonated(alice),
            10 * ONE_USDC
        );

        assertEq(
            tracker.donationCount(alice),
            3
        );
    }

    // 6. Donation history should preserve individual donations.

    function testDonationHistory() public {

        vm.startPrank(alice);

        tracker.donateETH{value: 1 ether}();

        tracker.donateUSDC(10 * ONE_USDC);

        vm.stopPrank();

        CharityDonationTracker.Donation[] memory history =
            tracker.getDonationHistory(alice);

        assertEq(history.length, 2);

        assertEq(history[0].donor, alice);
        assertEq(history[0].amount, 1 ether);
        assertEq(history[0].asset, address(0));

        assertEq(history[1].donor, alice);
        assertEq(history[1].amount, 10 * ONE_USDC);
        assertEq(history[1].asset, address(usdc));
    }

    // 7. Different donors should have separate histories.

    function testDonorsHaveSeparateHistories() public {

        vm.prank(alice);
        tracker.donateETH{value: 1 ether}();

        vm.prank(bob);
        tracker.donateETH{value: 2 ether}();

        CharityDonationTracker.Donation[] memory aliceHistory =
            tracker.getDonationHistory(alice);

        CharityDonationTracker.Donation[] memory bobHistory =
            tracker.getDonationHistory(bob);

        assertEq(aliceHistory.length, 1);
        assertEq(bobHistory.length, 1);

        assertEq(aliceHistory[0].amount, 1 ether);
        assertEq(bobHistory[0].amount, 2 ether);
    }

    // 8. Donations should continue after target is reached.

    function testDonationsContinueAfterTargetReached() public {

        vm.prank(alice);
        tracker.donateETH{value: 3 ether}();

        vm.prank(bob);
        tracker.donateETH{value: 1 ether}();

        assertEq(
            tracker.totalETHDonations(),
            4 ether
        );

        assertEq(
            tracker.fundraisingTarget(),
            3 ether
        );
    }

    // 9. USDC donation requires allowance.

    function testUSDCDonationWithoutApprovalReverts() public {

        address newDonor = makeAddr("newDonor");

        usdc.mint(newDonor, 10 * ONE_USDC);

        vm.prank(newDonor);

        vm.expectRevert();

        tracker.donateUSDC(10 * ONE_USDC);
    }

    // 10. Available ETH should equal allocated minus reserved.

    function testAvailableETHAccounting() public {

        vm.prank(alice);
        tracker.donateETH{value: 5 ether}();

        assertEq(
            tracker.getAvailableETH(),
            5 ether
        );
    }

    // 11. Available USDC should equal allocated minus reserved.

    function testAvailableUSDCAccounting() public {

        vm.prank(alice);
        tracker.donateUSDC(20 * ONE_USDC);

        assertEq(
            tracker.getAvailableUSDC(),
            20 * ONE_USDC
        );
    }

    // 12. Admin should be able to propose a payment.

    function testAdminCanProposePayment() public {

        vm.prank(alice);
        tracker.donateETH{value: 5 ether}();

        vm.prank(admin1);

        uint256 proposalId = tracker.proposePayment(
            vendor1,
            address(0),
            2 ether,
            "Purchase of medical supplies"
        );

        assertEq(proposalId, 1);

        CharityDonationTracker.PaymentProposal memory proposal =
            tracker.getPaymentProposal(proposalId);

        assertEq(proposal.vendor, vendor1);
        assertEq(proposal.amount, 2 ether);
        assertEq(proposal.asset, address(0));
        assertEq(proposal.approvals, 0);

        assertEq(
            uint256(proposal.status),
            uint256(CharityDonationTracker.PaymentStatus.Proposed)
        );
    }

    // 13. Non-admin cannot propose a payment.

    function testNonAdminCannotProposePayment() public {

        vm.prank(outsider);

        vm.expectRevert("Not an authorised admin");

        tracker.proposePayment(
            vendor1,
            address(0),
            1 ether,
            "Medical supplies"
        );
    }

    // 14. Unregistered vendor cannot receive a proposal.

    function testCannotProposePaymentToUnregisteredVendor() public {

        address unregisteredVendor = makeAddr("unregisteredVendor");

        vm.prank(admin1);

        vm.expectRevert("Vendor is not registered");

        tracker.proposePayment(
            unregisteredVendor,
            address(0),
            1 ether,
            "Medical supplies"
        );
    }

    // 15. Cannot propose unsupported assets.

    function testCannotProposeUnsupportedAsset() public {

        vm.prank(admin1);

        vm.expectRevert("Unsupported payment asset");

        tracker.proposePayment(
            vendor1,
            makeAddr("unsupportedToken"),
            1,
            "Purchase"
        );
    }

    // 16. Cannot propose zero payment.

    function testCannotProposeZeroPayment() public {

        vm.prank(admin1);

        vm.expectRevert("Invalid payment amount");

        tracker.proposePayment(
            vendor1,
            address(0),
            0,
            "Purchase"
        );
    }

    // 17. Cannot propose without a purpose.

    function testCannotProposeWithoutPurpose() public {

        vm.prank(admin1);

        vm.expectRevert("Payment purpose required");

        tracker.proposePayment(
            vendor1,
            address(0),
            1 ether,
            ""
        );
    }

    // 18. Cannot propose more than allocated funds.

    function testCannotProposeMoreThanAllocatedETH() public {

        vm.prank(alice);
        tracker.donateETH{value: 2 ether}();

        vm.prank(admin1);

        vm.expectRevert("Insufficient allocated ETH");

        tracker.proposePayment(
            vendor1,
            address(0),
            3 ether,
            "Medical supplies"
        );
    }

    // 19. Cannot propose more than allocated USDC.

    function testCannotProposeMoreThanAllocatedUSDC() public {

        vm.prank(alice);
        tracker.donateUSDC(2 * ONE_USDC);

        vm.prank(admin1);

        vm.expectRevert("Insufficient allocated USDC");

        tracker.proposePayment(
            vendor1,
            address(usdc),
            3 * ONE_USDC,
            "Medical supplies"
        );
    }

    function _createETHProposal(uint256 amount)
        internal
        returns (uint256 proposalId)
    {
        vm.prank(alice);
        tracker.donateETH{value: 5 ether}();

        vm.prank(admin1);

        proposalId = tracker.proposePayment(
            vendor1,
            address(0),
            amount,
            "Purchase of supplies"
        );
    }

    // 20. First approval should not reserve funds.

    function testFirstApprovalDoesNotReserveFunds() public {

        uint256 proposalId = _createETHProposal(3 ether);

        vm.prank(admin1);
        tracker.approvePayment(proposalId);

        assertEq(tracker.reservedETH(), 0);

        assertEq(
            tracker.getAvailableETH(),
            5 ether
        );

        assertEq(
            uint256(tracker.getPaymentProposal(proposalId).status),
            uint256(CharityDonationTracker.PaymentStatus.Proposed)
        );
    }

    // 21. Second approval should reserve funds.

    function testSecondApprovalReservesFunds() public {

        uint256 proposalId = _createETHProposal(3 ether);

        vm.prank(admin1);
        tracker.approvePayment(proposalId);

        vm.prank(admin2);
        tracker.approvePayment(proposalId);

        assertEq(tracker.reservedETH(), 3 ether);

        assertEq(
            tracker.getAvailableETH(),
            2 ether
        );

        assertEq(
            uint256(tracker.getPaymentProposal(proposalId).status),
            uint256(CharityDonationTracker.PaymentStatus.Approved)
        );
    }

    // 22. Same admin cannot approve twice.

    function testAdminCannotApproveTwice() public {

        uint256 proposalId = _createETHProposal(3 ether);

        vm.prank(admin1);
        tracker.approvePayment(proposalId);

        vm.prank(admin1);

        vm.expectRevert("Already approved");

        tracker.approvePayment(proposalId);
    }

    // 23. Non-admin cannot approve.

    function testNonAdminCannotApprove() public {

        uint256 proposalId = _createETHProposal(3 ether);

        vm.prank(outsider);

        vm.expectRevert("Not an authorised admin");

        tracker.approvePayment(proposalId);
    }

    // 24. A proposal cannot receive a second approval
    // if insufficient available funds exist.

    function testSecondApprovalFailsIfInsufficientAvailableFunds() public {

        vm.prank(alice);
        tracker.donateETH{value: 5 ether}();

        vm.prank(admin1);
        uint256 proposalA = tracker.proposePayment(
            vendor1,
            address(0),
            3 ether,
            "Payment A"
        );

        vm.prank(admin1);
        uint256 proposalB = tracker.proposePayment(
            vendor2,
            address(0),
            3 ether,
            "Payment B"
        );

        // Payment A gets two approvals.
        vm.prank(admin1);
        tracker.approvePayment(proposalA);

        vm.prank(admin2);
        tracker.approvePayment(proposalA);

        assertEq(tracker.reservedETH(), 3 ether);

        // Payment B gets its first approval.
        vm.prank(admin1);
        tracker.approvePayment(proposalB);

        // Second approval must fail because only 2 ETH is available.
        vm.prank(admin2);

        vm.expectRevert("Insufficient available ETH");

        tracker.approvePayment(proposalB);

        // Failed transaction must not record the second approval.
        assertEq(
            tracker.getPaymentProposal(proposalB).approvals,
            1
        );

        assertEq(tracker.reservedETH(), 3 ether);
    }

    // 25. Payment B can receive second approval after
    // additional funds arrive.

    function testPendingPaymentCanBeApprovedAfterMoreDonations() public {

        vm.prank(alice);
        tracker.donateETH{value: 5 ether}();

        vm.prank(admin1);
        uint256 proposalA = tracker.proposePayment(
            vendor1,
            address(0),
            3 ether,
            "Payment A"
        );

        vm.prank(admin1);
        uint256 proposalB = tracker.proposePayment(
            vendor2,
            address(0),
            3 ether,
            "Payment B"
        );

        vm.prank(admin1);
        tracker.approvePayment(proposalA);

        vm.prank(admin2);
        tracker.approvePayment(proposalA);

        vm.prank(admin1);
        tracker.approvePayment(proposalB);

        // Additional 1 ETH is donated.
        vm.prank(bob);
        tracker.donateETH{value: 1 ether}();

        // Available funds are now 3 ETH.
        vm.prank(admin2);
        tracker.approvePayment(proposalB);

        assertEq(tracker.reservedETH(), 6 ether);
        assertEq(tracker.getAvailableETH(), 0);
    }

    function _approveETHProposal(uint256 amount)
        internal
        returns (uint256 proposalId)
    {
        proposalId = _createETHProposal(amount);

        vm.prank(admin1);
        tracker.approvePayment(proposalId);

        vm.prank(admin2);
        tracker.approvePayment(proposalId);
    }

    // 26. Any admin can execute after two approvals.

    function testThirdAdminCanExecuteApprovedPayment() public {

        uint256 proposalId = _approveETHProposal(3 ether);

        uint256 vendorBalanceBefore = vendor1.balance;

        vm.prank(admin3);
        tracker.executePayment(proposalId);

        assertEq(
            vendor1.balance,
            vendorBalanceBefore + 3 ether
        );

        assertEq(tracker.allocatedETH(), 2 ether);
        assertEq(tracker.reservedETH(), 0);

        assertEq(
            uint256(tracker.getPaymentProposal(proposalId).status),
            uint256(CharityDonationTracker.PaymentStatus.Executed)
        );
    }

    // 27. Non-admin cannot execute.

    function testNonAdminCannotExecutePayment() public {

        uint256 proposalId = _approveETHProposal(3 ether);

        vm.prank(outsider);

        vm.expectRevert("Not an authorised admin");

        tracker.executePayment(proposalId);
    }

    // 28. Payment cannot execute without two approvals.

    function testCannotExecuteUnapprovedPayment() public {

        uint256 proposalId = _createETHProposal(3 ether);

        vm.prank(admin1);
        tracker.approvePayment(proposalId);

        vm.prank(admin3);

        vm.expectRevert("Payment not approved");

        tracker.executePayment(proposalId);
    }

    // 29. Payment cannot be executed twice.

    function testCannotExecutePaymentTwice() public {

        uint256 proposalId = _approveETHProposal(3 ether);

        vm.prank(admin3);
        tracker.executePayment(proposalId);

        vm.prank(admin3);

        vm.expectRevert("Payment not approved");

        tracker.executePayment(proposalId);
    }

    // 30. Vendor must still be registered at execution.

    function testVendorMustStillBeRegisteredAtExecution() public {

        uint256 proposalId = _approveETHProposal(3 ether);

        registry.removeVendor(vendor1);

        vm.prank(admin3);

        vm.expectRevert("Vendor is no longer registered");

        tracker.executePayment(proposalId);

        // The failed execution must preserve the reservation.
        assertEq(tracker.reservedETH(), 3 ether);
    }

    // 31. USDC payment should transfer the correct amount.

    function testUSDCPaymentExecution() public {

        vm.prank(alice);
        tracker.donateUSDC(10 * ONE_USDC);

        vm.prank(admin1);
        uint256 proposalId = tracker.proposePayment(
            vendor1,
            address(usdc),
            4 * ONE_USDC,
            "Purchase of food supplies"
        );

        vm.prank(admin1);
        tracker.approvePayment(proposalId);

        vm.prank(admin2);
        tracker.approvePayment(proposalId);

        uint256 vendorBalanceBefore = usdc.balanceOf(vendor1);

        vm.prank(admin3);
        tracker.executePayment(proposalId);

        assertEq(
            usdc.balanceOf(vendor1),
            vendorBalanceBefore + 4 * ONE_USDC
        );

        assertEq(tracker.allocatedUSDC(), 6 * ONE_USDC);
        assertEq(tracker.reservedUSDC(), 0);
    }

    // 32. First admin proposes a new target.

    function testAdminCanProposeTargetUpdate() public {

        vm.prank(admin1);

        uint256 targetProposalId =
            tracker.proposeTargetUpdate(5 ether);

        assertEq(
            tracker.proposedTargets(targetProposalId),
            5 ether
        );

        assertEq(
            tracker.targetApprovalCount(targetProposalId),
            1
        );

        assertTrue(
            tracker.hasApprovedTarget(targetProposalId, admin1)
        );
    }

    // 33. Second admin approval updates the target.

    function testSecondApprovalUpdatesTarget() public {

        vm.prank(admin1);

        uint256 targetProposalId =
            tracker.proposeTargetUpdate(5 ether);

        vm.prank(admin2);

        tracker.approveTargetUpdate(targetProposalId);

        assertEq(
            tracker.fundraisingTarget(),
            5 ether
        );
    }

    // 34. Same admin cannot approve target update twice.

    function testCannotApproveTargetUpdateTwice() public {

        vm.prank(admin1);

        uint256 targetProposalId =
            tracker.proposeTargetUpdate(5 ether);

        vm.prank(admin1);

        vm.expectRevert("Already approved");

        tracker.approveTargetUpdate(targetProposalId);
    }

    // 35. Non-admin cannot update target.

    function testNonAdminCannotProposeTargetUpdate() public {

        vm.prank(outsider);

        vm.expectRevert("Not an authorised admin");

        tracker.proposeTargetUpdate(5 ether);
    }

    // 36. Third admin can approve target update.

    function testThirdAdminCanApproveTargetUpdate() public {

        vm.prank(admin1);

        uint256 targetProposalId =
            tracker.proposeTargetUpdate(7 ether);

        vm.prank(admin3);

        tracker.approveTargetUpdate(targetProposalId);

        assertEq(
            tracker.fundraisingTarget(),
            7 ether
        );
    }

    // 37. Duplicate admin addresses should be rejected.

    function testConstructorRejectsDuplicateAdmins() public {

        vm.expectRevert("Admins must be distinct");

        new CharityDonationTracker(
            admin1,
            admin1,
            admin3,
            address(usdc),
            address(registry),
            initialTarget
        );
    }

    // 38. Zero admin address should be rejected.

    function testConstructorRejectsZeroAdmin() public {

        vm.expectRevert("Invalid admin address");

        new CharityDonationTracker(
            address(0),
            admin2,
            admin3,
            address(usdc),
            address(registry),
            initialTarget
        );
    }
}
