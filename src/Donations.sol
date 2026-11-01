
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {vendorRegistry} from "./VendorRegistry.sol";

contract CharityDonationTracker {

    using SafeERC20 for IERC20;

    uint256 public fundraisingTarget;

    address public admin1;
    address public admin2;
    address public admin3;

    IERC20 public usdcToken;
    vendorRegistry public registry;

    enum PaymentStatus {
        Proposed,
        Approved,
        Executed
    }

    struct Donation {
        address donor;
        uint256 amount;
        uint256 timestamp;
        address asset;
    }

    struct PaymentProposal {
        address vendor;
        address asset;
        uint256 amount;
        string purpose;
        uint256 approvals;
        PaymentStatus status;
        uint256 timestamp;
    }

    mapping(address => Donation[]) internal donationHistory;

    mapping(address => uint256) public totalETHDonated;
    mapping(address => uint256) public totalUSDCDonated;

    mapping(address => uint256) public donationCount;

    uint256 public totalETHDonations;
    uint256 public totalUSDCDonations;

    uint256 public allocatedETH;
    uint256 public allocatedUSDC;

    uint256 public reservedETH;
    uint256 public reservedUSDC;

    mapping(uint256 => PaymentProposal) internal paymentProposals;

    mapping(uint256 => mapping(address => bool)) public hasApproved;

    uint256 public proposalCount;

    // Fundraising target update proposals

    mapping(uint256 => uint256) public proposedTargets;

    mapping(uint256 => uint256) public targetApprovalCount;

    mapping(uint256 => mapping(address => bool))
        public hasApprovedTarget;

    uint256 public targetProposalCount;

    event DonationReceived(
        address indexed donor,
        address indexed asset,
        uint256 amount,
        uint256 timestamp
    );

    event PaymentProposed(
        uint256 indexed proposalId,
        address indexed vendor,
        address asset,
        uint256 amount,
        string purpose
    );

    event PaymentApproved(
        uint256 indexed proposalId,
        address indexed admin,
        uint256 approvalCount
    );

    event FundsWithdrawn(
        uint256 indexed proposalId,
        address indexed vendor,
        address asset,
        uint256 amount,
        string purpose
    );

    event TargetUpdateProposed(
        uint256 indexed proposalId,
        uint256 proposedTarget
    );

    event TargetUpdated(
        uint256 indexed proposalId,
        uint256 oldTarget,
        uint256 newTarget
    );

    modifier onlyAdmin() {
        require(
            msg.sender == admin1 ||
            msg.sender == admin2 ||
            msg.sender == admin3,
            "Not an authorised admin"
        );
        _;
    }

    constructor(
        address _admin1,
        address _admin2,
        address _admin3,
        address _usdcToken,
        address _vendorRegistry,
        uint256 _fundraisingTarget
    ) {

        require(
            _admin1 != address(0) &&
            _admin2 != address(0) &&
            _admin3 != address(0),
            "Invalid admin address"
        );

        require(
            _admin1 != _admin2 &&
            _admin1 != _admin3 &&
            _admin2 != _admin3,
            "Admins must be distinct"
        );

        require(
            _usdcToken != address(0) &&
            _usdcToken.code.length > 0,
            "Invalid USDC address"
        );

        require(
            _vendorRegistry != address(0) &&
            _vendorRegistry.code.length > 0,
            "Invalid registry address"
        );

        admin1 = _admin1;
        admin2 = _admin2;
        admin3 = _admin3;

        usdcToken = IERC20(_usdcToken);

        registry = vendorRegistry(_vendorRegistry);

        fundraisingTarget = _fundraisingTarget;
    }
    // ETH donations

    function donateETH() external payable {

        require(
            msg.value > 0,
            "Donation must be greater than zero"
        );

        Donation memory newDonation = Donation({
            donor: msg.sender,
            amount: msg.value,
            timestamp: block.timestamp,
            asset: address(0)
        });

        donationHistory[msg.sender].push(newDonation);

        totalETHDonated[msg.sender] += msg.value;

        donationCount[msg.sender]++;

        totalETHDonations += msg.value;

        allocatedETH += msg.value;

        emit DonationReceived(
            msg.sender,
            address(0),
            msg.value,
            block.timestamp
        );
    }

    // USDC donations

    function donateUSDC(uint256 amount) external {

        require(
            amount > 0,
            "Donation must be greater than zero"
        );

        uint256 balanceBefore = usdcToken.balanceOf(address(this));

        usdcToken.safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        uint256 balanceAfter = usdcToken.balanceOf(address(this));

        uint256 receivedAmount = balanceAfter - balanceBefore;

        require(
            receivedAmount > 0,
            "No USDC received"
        );

        Donation memory newDonation = Donation({
            donor: msg.sender,
            amount: receivedAmount,
            timestamp: block.timestamp,
            asset: address(usdcToken)
        });

        donationHistory[msg.sender].push(newDonation);

        totalUSDCDonated[msg.sender] += receivedAmount;

        donationCount[msg.sender]++;

        totalUSDCDonations += receivedAmount;

        allocatedUSDC += receivedAmount;

        emit DonationReceived(
            msg.sender,
            address(usdcToken),
            receivedAmount,
            block.timestamp
        );
    }

    function getDonationHistory(address donor)
        external
        view
        returns (Donation[] memory)
    {
        return donationHistory[donor];
    }

    function getAvailableETH()
        public
        view
        returns (uint256)
    {
        return allocatedETH - reservedETH;
    }

    function getAvailableUSDC()
        public
        view
        returns (uint256)
    {
        return allocatedUSDC - reservedUSDC;
    }

    function proposePayment(
        address vendor,
        address asset,
        uint256 amount,
        string calldata purpose
    )
        external
        onlyAdmin
        returns (uint256 proposalId)
    {

        require(
            registry.isRegistered(vendor),
            "Vendor is not registered"
        );

        require(
            amount > 0,
            "Invalid payment amount"
        );

        require(
            bytes(purpose).length > 0,
            "Payment purpose required"
        );

        require(
            asset == address(0) ||
            asset == address(usdcToken),
            "Unsupported payment asset"
        );

        // Check the cause's allocated balance,
        // not the total contract balance.

        if (asset == address(0)) {

            require(
                amount <= allocatedETH,
                "Insufficient allocated ETH"
            );

        } else {

            require(
                amount <= allocatedUSDC,
                "Insufficient allocated USDC"
            );

        }

        proposalId = ++proposalCount;

        paymentProposals[proposalId] = PaymentProposal({
            vendor: vendor,
            asset: asset,
            amount: amount,
            purpose: purpose,
            approvals: 0,
            status: PaymentStatus.Proposed,
            timestamp: block.timestamp
        });

        emit PaymentProposed(
            proposalId,
            vendor,
            asset,
            amount,
            purpose
        );
    }

    function approvePayment(uint256 proposalId)
        external
        onlyAdmin
    {

        PaymentProposal storage proposal =
            paymentProposals[proposalId];

        require(
            proposalId > 0 &&
            proposalId <= proposalCount,
            "Invalid proposal"
        );

        require(
            proposal.status == PaymentStatus.Proposed,
            "Proposal is not pending"
        );

        require(
            !hasApproved[proposalId][msg.sender],
            "Already approved"
        );

        hasApproved[proposalId][msg.sender] = true;

        proposal.approvals++;

        // The second approval reserves the funds.

        if (proposal.approvals == 2) {

            require(
                registry.isRegistered(proposal.vendor),
                "Vendor is no longer registered"
            );

            if (proposal.asset == address(0)) {

                require(
                    getAvailableETH() >= proposal.amount,
                    "Insufficient available ETH"
                );

                reservedETH += proposal.amount;

            } else {

                require(
                    getAvailableUSDC() >= proposal.amount,
                    "Insufficient available USDC"
                );

                reservedUSDC += proposal.amount;

            }

            proposal.status = PaymentStatus.Approved;
        }

        emit PaymentApproved(
            proposalId,
            msg.sender,
            proposal.approvals
        );
    }

    function executePayment(uint256 proposalId)
        external
        onlyAdmin
    {

        require(
            proposalId > 0 &&
            proposalId <= proposalCount,
            "Invalid proposal"
        );

        PaymentProposal storage proposal =
            paymentProposals[proposalId];

        require(
            proposal.status == PaymentStatus.Approved,
            "Payment not approved"
        );

        require(
            registry.isRegistered(proposal.vendor),
            "Vendor is no longer registered"
        );

        uint256 amount = proposal.amount;

        address vendor = proposal.vendor;

        address asset = proposal.asset;

        // Mark as executed and update accounting
        // before making the external transfer.

        proposal.status = PaymentStatus.Executed;

        if (asset == address(0)) {

            require(
                address(this).balance >= amount,
                "Insufficient contract ETH"
            );

            reservedETH -= amount;

            allocatedETH -= amount;

            (bool success, ) = payable(vendor).call{
                value: amount
            }("");

            require(
                success,
                "ETH transfer failed"
            );

        } else {

            require(
                usdcToken.balanceOf(address(this)) >= amount,
                "Insufficient contract USDC"
            );

            reservedUSDC -= amount;

            allocatedUSDC -= amount;

            usdcToken.safeTransfer(
                vendor,
                amount
            );

        }

        emit FundsWithdrawn(
            proposalId,
            vendor,
            asset,
            amount,
            proposal.purpose
        );
    }

    function proposeTargetUpdate(uint256 newTarget)
        external
        onlyAdmin
        returns (uint256 targetProposalId)
    {

        targetProposalId = ++targetProposalCount;

        proposedTargets[targetProposalId] = newTarget;

        hasApprovedTarget[targetProposalId][msg.sender] = true;

        targetApprovalCount[targetProposalId] = 1;

        emit TargetUpdateProposed(
            targetProposalId,
            newTarget
        );
    }

    function approveTargetUpdate(uint256 targetProposalId)
        external
        onlyAdmin
    {

        require(
            targetProposalId > 0 &&
            targetProposalId <= targetProposalCount,
            "Invalid target proposal"
        );

        require(
            proposedTargets[targetProposalId] != type(uint256).max,
            "Target proposal already executed"
        );

        require(
            !hasApprovedTarget[targetProposalId][msg.sender],
            "Already approved"
        );

        hasApprovedTarget[targetProposalId][msg.sender] = true;

        targetApprovalCount[targetProposalId]++;

        if (targetApprovalCount[targetProposalId] == 2) {

            uint256 oldTarget = fundraisingTarget;

            uint256 newTarget = proposedTargets[targetProposalId];

            fundraisingTarget = newTarget;

            // Mark the proposal as executed.

            proposedTargets[targetProposalId] = type(uint256).max;

            emit TargetUpdated(
                targetProposalId,
                oldTarget,
                newTarget
            );
        }
    }

    function getPaymentProposal(uint256 proposalId)
        external
        view
        returns (PaymentProposal memory)
    {
        require(
            proposalId > 0 &&
            proposalId <= proposalCount,
            "Invalid proposal"
        );

        return paymentProposals[proposalId];
    }

}
