// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAgentRegistryV020 {
    struct Agent {
        uint256 id;
        address owner;
        string name;
        string metadataURI;
        bool active;
        uint256 createdAt;
    }
    function getAgent(uint256 agentId) external view returns (Agent memory);
}

/// @notice Experimental settlement protocol. Test environments only.
/// @dev The arbitrator and timeout allocation are agreed by the provider at acceptance.
contract TaskProtocolV020 {
    IAgentRegistryV020 public immutable registry;
    uint256 public constant REVIEW_PERIOD = 48 hours;
    uint256 public constant DISPUTE_PERIOD = 7 days;
    uint256 public constant MAX_DURATION = 30 days;

    // Preserve v0.1 numeric values for existing status names.
    enum TaskStatus { Created, Submitted, Completed, Refunded, Accepted, Disputed, Cancelled, Settled }
    struct Task {
        uint256 id;
        uint256 requesterAgentId;
        uint256 providerAgentId;
        address requester;
        address provider;
        string description;
        string resultURI;
        uint256 payment;
        uint256 createdAt;
        uint256 deadline;
        TaskStatus status;
        address arbitrator;
        uint256 reviewDeadline;
        uint256 disputeDeadline;
        bytes32 resultHash;
        bytes32 disputeReasonHash;
        uint256 timeoutProviderBps;
        uint256 proposedProviderAmount;
        address settlementProposer;
    }

    error InvalidRegistry();
    error InvalidAgents();
    error PaymentRequired();
    error DescriptionRequired();
    error InvalidDuration();
    error InvalidArbitrator();
    error InvalidAllocation();
    error TaskNotFound();
    error Unauthorized();
    error InvalidStatus();
    error DeadlinePassed();
    error DeadlineNotReached();
    error ResultRequired();
    error ReasonRequired();
    error NoPaymentAvailable();
    error WithdrawalFailed();
    error InvalidRecipient();
    error NoSettlementOffer();

    uint256 public taskCount;
    uint256 public totalEscrow;
    uint256 public totalPendingWithdrawals;
    mapping(uint256 => Task) private tasks;
    mapping(address => uint256) public pendingWithdrawals;

    event TaskCreated(uint256 indexed taskId, uint256 indexed requesterAgentId, uint256 indexed providerAgentId, uint256 payment);
    event TermsSet(uint256 indexed taskId, address indexed arbitrator, uint256 timeoutProviderBps);
    event TaskAccepted(uint256 indexed taskId);
    event TaskSubmitted(uint256 indexed taskId, string resultURI);
    event ResultCommitted(uint256 indexed taskId, bytes32 resultHash, uint256 reviewDeadline);
    event TaskCompleted(uint256 indexed taskId, uint256 payment);
    event TaskRefunded(uint256 indexed taskId, uint256 payment);
    event TaskCancelled(uint256 indexed taskId);
    event DisputeRaised(uint256 indexed taskId, bytes32 reasonHash, uint256 disputeDeadline);
    event SettlementProposed(uint256 indexed taskId, address indexed proposer, uint256 providerAmount);
    event SettlementOfferCancelled(uint256 indexed taskId);
    event TaskSettled(uint256 indexed taskId, uint256 providerAmount, uint256 requesterAmount, TaskStatus status);
    event PaymentWithdrawn(address indexed recipient, uint256 amount);
    event WithdrawalRecipient(address indexed owner, address indexed recipient, uint256 amount);

    constructor(address registryAddress) {
        if (registryAddress.code.length == 0) revert InvalidRegistry();
        registry = IAgentRegistryV020(registryAddress);
    }
    modifier taskExists(uint256 taskId) {
        if (taskId == 0 || taskId > taskCount) revert TaskNotFound();
        _;
    }

    /// @notice deadline starts at creation; acceptance does not extend it.
    /// @param timeoutProviderBps Provider's share if arbitrator fails to resolve in seven days.
    function createTask(
        uint256 requesterAgentId,
        uint256 providerAgentId,
        string calldata description,
        uint256 durationSeconds,
        address arbitrator,
        uint256 timeoutProviderBps
    ) external payable returns (uint256 taskId) {
        if (requesterAgentId == providerAgentId) revert InvalidAgents();
        if (msg.value == 0) revert PaymentRequired();
        if (bytes(description).length == 0) revert DescriptionRequired();
        if (durationSeconds == 0 || durationSeconds > MAX_DURATION) revert InvalidDuration();
        if (timeoutProviderBps > 10_000) revert InvalidAllocation();
        IAgentRegistryV020.Agent memory r = registry.getAgent(requesterAgentId);
        IAgentRegistryV020.Agent memory p = registry.getAgent(providerAgentId);
        if (!r.active || !p.active || r.owner == address(0) || p.owner == address(0) || r.owner == p.owner) revert InvalidAgents();
        if (r.owner != msg.sender) revert Unauthorized();
        if (arbitrator == address(0) || arbitrator == r.owner || arbitrator == p.owner || arbitrator == address(this)) revert InvalidArbitrator();
        taskId = ++taskCount;
        Task storage t = tasks[taskId];
        t.id = taskId;
        t.requesterAgentId = requesterAgentId;
        t.providerAgentId = providerAgentId;
        t.requester = r.owner;
        t.provider = p.owner;
        t.description = description;
        t.payment = msg.value;
        t.createdAt = block.timestamp;
        t.deadline = block.timestamp + durationSeconds;
        t.status = TaskStatus.Created;
        t.arbitrator = arbitrator;
        t.timeoutProviderBps = timeoutProviderBps;
        totalEscrow += msg.value;
        emit TaskCreated(taskId, requesterAgentId, providerAgentId, msg.value);
        emit TermsSet(taskId, arbitrator, timeoutProviderBps);
    }

    function acceptTask(uint256 taskId) external taskExists(taskId) {
        Task storage t = tasks[taskId];
        if (msg.sender != t.provider) revert Unauthorized();
        if (t.status != TaskStatus.Created) revert InvalidStatus();
        if (block.timestamp >= t.deadline) revert DeadlinePassed();
        t.status = TaskStatus.Accepted;
        emit TaskAccepted(taskId);
    }

    function cancelTask(uint256 taskId) external taskExists(taskId) {
        Task storage t = tasks[taskId];
        if (msg.sender != t.requester) revert Unauthorized();
        if (t.status != TaskStatus.Created) revert InvalidStatus();
        _settle(t, 0, TaskStatus.Cancelled);
        emit TaskCancelled(taskId);
    }

    /// @param resultHash Hash of the actual result bytes, computed off-chain.
    function submitResult(uint256 taskId, string calldata resultURI, bytes32 resultHash) external taskExists(taskId) {
        Task storage t = tasks[taskId];
        if (msg.sender != t.provider) revert Unauthorized();
        if (t.status != TaskStatus.Accepted) revert InvalidStatus();
        if (block.timestamp >= t.deadline) revert DeadlinePassed();
        if (bytes(resultURI).length == 0 || resultHash == bytes32(0)) revert ResultRequired();
        t.resultURI = resultURI;
        t.resultHash = resultHash;
        t.reviewDeadline = block.timestamp + REVIEW_PERIOD;
        t.status = TaskStatus.Submitted;
        emit TaskSubmitted(taskId, resultURI);
        emit ResultCommitted(taskId, resultHash, t.reviewDeadline);
    }

    function approveTask(uint256 taskId) external taskExists(taskId) {
        Task storage t = tasks[taskId];
        if (msg.sender != t.requester) revert Unauthorized();
        if (t.status != TaskStatus.Submitted) revert InvalidStatus();
        _settle(t, t.payment, TaskStatus.Completed);
    }

    /// @notice Anyone may finalize a non-disputed delivery after its review period.
    function claimPayment(uint256 taskId) external taskExists(taskId) {
        Task storage t = tasks[taskId];
        if (t.status != TaskStatus.Submitted) revert InvalidStatus();
        if (block.timestamp < t.reviewDeadline) revert DeadlineNotReached();
        _settle(t, t.payment, TaskStatus.Completed);
    }

    /// @notice Only undelivered tasks can expire into a refund; anyone may trigger it.
    function refundTask(uint256 taskId) external taskExists(taskId) {
        Task storage t = tasks[taskId];
        if (t.status != TaskStatus.Created && t.status != TaskStatus.Accepted) revert InvalidStatus();
        if (block.timestamp < t.deadline) revert DeadlineNotReached();
        _settle(t, 0, TaskStatus.Refunded);
    }

    function raiseDispute(uint256 taskId, bytes32 reasonHash) external taskExists(taskId) {
        Task storage t = tasks[taskId];
        if (msg.sender != t.requester) revert Unauthorized();
        if (t.status != TaskStatus.Submitted) revert InvalidStatus();
        if (block.timestamp >= t.reviewDeadline) revert DeadlinePassed();
        if (reasonHash == bytes32(0)) revert ReasonRequired();
        t.status = TaskStatus.Disputed;
        t.disputeReasonHash = reasonHash;
        t.disputeDeadline = block.timestamp + DISPUTE_PERIOD;
        emit DisputeRaised(taskId, reasonHash, t.disputeDeadline);
    }

    function resolveDispute(uint256 taskId, uint256 providerAmount) external taskExists(taskId) {
        Task storage t = tasks[taskId];
        if (msg.sender != t.arbitrator) revert Unauthorized();
        if (t.status != TaskStatus.Disputed) revert InvalidStatus();
        if (block.timestamp >= t.disputeDeadline) revert DeadlinePassed();
        _resolve(t, providerAmount);
    }

    /// @notice Either party can propose an exact allocation; only the other can accept.
    function proposeSettlement(uint256 taskId, uint256 providerAmount) external taskExists(taskId) {
        Task storage t = tasks[taskId];
        _checkDisputedParty(t);
        if (providerAmount > t.payment) revert InvalidAllocation();
        t.proposedProviderAmount = providerAmount;
        t.settlementProposer = msg.sender;
        emit SettlementProposed(taskId, msg.sender, providerAmount);
    }

    function cancelSettlementOffer(uint256 taskId) external taskExists(taskId) {
        Task storage t = tasks[taskId];
        _checkDisputedParty(t);
        if (t.settlementProposer != msg.sender) revert Unauthorized();
        t.settlementProposer = address(0);
        t.proposedProviderAmount = 0;
        emit SettlementOfferCancelled(taskId);
    }

    function acceptSettlement(uint256 taskId, uint256 expectedProviderAmount) external taskExists(taskId) {
        Task storage t = tasks[taskId];
        _checkDisputedParty(t);
        if (t.settlementProposer == address(0)) revert NoSettlementOffer();
        if (t.settlementProposer == msg.sender) revert Unauthorized();
        if (t.proposedProviderAmount != expectedProviderAmount) revert InvalidAllocation();
        _resolve(t, expectedProviderAmount);
    }

    /// @notice Liveness fallback, not proof of correct work. Terms were accepted before work.
    function finalizeDisputeTimeout(uint256 taskId) external taskExists(taskId) {
        Task storage t = tasks[taskId];
        if (t.status != TaskStatus.Disputed) revert InvalidStatus();
        if (block.timestamp < t.disputeDeadline) revert DeadlineNotReached();
        // Avoid overflow even for extreme uint256 values.
        uint256 share = (t.payment / 10_000) * t.timeoutProviderBps
            + ((t.payment % 10_000) * t.timeoutProviderBps) / 10_000;
        _resolve(t, share);
    }

    function _checkDisputedParty(Task storage t) private view {
        if (t.status != TaskStatus.Disputed) revert InvalidStatus();
        if (msg.sender != t.requester && msg.sender != t.provider) revert Unauthorized();
        if (block.timestamp >= t.disputeDeadline) revert DeadlinePassed();
    }

    function _resolve(Task storage t, uint256 providerAmount) private {
        if (providerAmount > t.payment) revert InvalidAllocation();
        TaskStatus finalStatus = providerAmount == 0 ? TaskStatus.Refunded
            : providerAmount == t.payment ? TaskStatus.Completed : TaskStatus.Settled;
        _settle(t, providerAmount, finalStatus);
    }

    function _settle(Task storage t, uint256 providerAmount, TaskStatus finalStatus) private {
        uint256 requesterAmount = t.payment - providerAmount;
        t.status = finalStatus;
        t.settlementProposer = address(0);
        t.proposedProviderAmount = 0;
        totalEscrow -= t.payment;
        totalPendingWithdrawals += t.payment;
        pendingWithdrawals[t.provider] += providerAmount;
        pendingWithdrawals[t.requester] += requesterAmount;
        if (finalStatus == TaskStatus.Completed) emit TaskCompleted(t.id, providerAmount);
        if (finalStatus == TaskStatus.Refunded || finalStatus == TaskStatus.Cancelled) emit TaskRefunded(t.id, requesterAmount);
        emit TaskSettled(t.id, providerAmount, requesterAmount, finalStatus);
    }

    function withdrawPayment() external { _withdraw(payable(msg.sender)); }

    /// @notice Allows a contract wallet unable to receive ETH to direct its own credit elsewhere.
    function withdrawPaymentTo(address payable recipient) external { _withdraw(recipient); }

    function _withdraw(address payable recipient) private {
        if (recipient == address(0) || recipient == address(this)) revert InvalidRecipient();
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert NoPaymentAvailable();
        pendingWithdrawals[msg.sender] = 0;
        totalPendingWithdrawals -= amount;
        (bool success,) = recipient.call{value: amount}("");
        if (!success) revert WithdrawalFailed();
        emit PaymentWithdrawn(msg.sender, amount);
        emit WithdrawalRecipient(msg.sender, recipient, amount);
    }

    function getTask(uint256 taskId) external view taskExists(taskId) returns (Task memory) { return tasks[taskId]; }
    function version() external pure returns (string memory) { return "0.2.0"; }
