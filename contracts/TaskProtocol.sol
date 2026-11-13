// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Quoraxis Task Protocol
 * @notice Experimental task and settlement protocol.
 * @dev Version 0.1.0 - Test environment only.
 */

interface IAgentRegistry {

    struct Agent {
        uint256 id;
        address owner;
        string name;
        string metadataURI;
        bool active;
        uint256 createdAt;
    }

    function getAgent(
        uint256 agentId
    ) external view returns (Agent memory);
}

contract TaskProtocol {

    IAgentRegistry public immutable registry;

    enum TaskStatus {
        Created,
        Submitted,
        Completed,
        Refunded
    }

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
    }

    uint256 public taskCount;

    mapping(uint256 => Task) private tasks;

    mapping(address => uint256)
        public pendingWithdrawals;

    event TaskCreated(
        uint256 indexed taskId,
        uint256 indexed requesterAgentId,
        uint256 indexed providerAgentId,
        uint256 payment
    );

    event TaskSubmitted(
        uint256 indexed taskId,
        string resultURI
    );

    event TaskCompleted(
        uint256 indexed taskId,
        uint256 payment
    );

    event TaskRefunded(
        uint256 indexed taskId,
        uint256 payment
    );

    event PaymentWithdrawn(
        address indexed recipient,
        uint256 amount
    );

    constructor(address registryAddress) {

        require(
            registryAddress.code.length > 0,
            "Invalid registry"
        );

        registry = IAgentRegistry(
            registryAddress
        );
    }

    modifier taskExists(uint256 taskId) {

        require(
            taskId > 0 && taskId <= taskCount,
            "Task does not exist"
        );

        _;
    }

    function createTask(
        uint256 requesterAgentId,
        uint256 providerAgentId,
        string calldata description,
        uint256 durationSeconds
    ) external payable returns (uint256) {

        require(
            requesterAgentId != providerAgentId,
            "Agents must be different"
        );

        require(
            msg.value > 0,
            "Payment required"
        );

        require(
            bytes(description).length > 0,
            "Description required"
        );

        require(
            durationSeconds > 0 &&
            durationSeconds <= 30 days,
            "Invalid duration"
        );

        IAgentRegistry.Agent memory requester =
            registry.getAgent(requesterAgentId);

        IAgentRegistry.Agent memory provider =
            registry.getAgent(providerAgentId);

        require(
            requester.active && provider.active,
            "Agent is inactive"
        );

        require(
            requester.owner == msg.sender,
            "Not requester owner"
        );

        require(
            requester.owner != provider.owner,
            "Different owners required"
        );

        taskCount++;

        uint256 taskId = taskCount;

        Task storage task = tasks[taskId];

        task.id = taskId;
        task.requesterAgentId = requesterAgentId;
        task.providerAgentId = providerAgentId;
        task.requester = requester.owner;
        task.provider = provider.owner;
        task.description = description;
        task.payment = msg.value;
        task.createdAt = block.timestamp;
        task.deadline =
            block.timestamp + durationSeconds;
        task.status = TaskStatus.Created;

        emit TaskCreated(
            taskId,
            requesterAgentId,
            providerAgentId,
            msg.value
        );

        return taskId;
    }

    function submitResult(
        uint256 taskId,
        string calldata resultURI
    ) external taskExists(taskId) {

        Task storage task = tasks[taskId];

        require(
            msg.sender == task.provider,
            "Not task provider"
        );

        require(
            task.status == TaskStatus.Created,
            "Invalid task status"
        );

        require(
            block.timestamp < task.deadline,
            "Task expired"
        );

        require(
            bytes(resultURI).length > 0,
            "Result required"
        );

        task.resultURI = resultURI;
        task.status = TaskStatus.Submitted;

        emit TaskSubmitted(
            taskId,
            resultURI
        );
    }

    function approveTask(
        uint256 taskId
    ) external taskExists(taskId) {

        Task storage task = tasks[taskId];

        require(
            msg.sender == task.requester,
            "Not task requester"
        );

        require(
            task.status == TaskStatus.Submitted,
            "Result not submitted"
        );

        require(
            block.timestamp < task.deadline,
            "Task expired"
        );

        task.status = TaskStatus.Completed;

        pendingWithdrawals[task.provider] +=
            task.payment;

        emit TaskCompleted(
            taskId,
            task.payment
        );
    }

    function refundTask(
        uint256 taskId
    ) external taskExists(taskId) {

        Task storage task = tasks[taskId];

        require(
            msg.sender == task.requester,
            "Not task requester"
        );

        require(
            block.timestamp >= task.deadline,
            "Task not expired"
        );

        require(
            task.status == TaskStatus.Created ||
            task.status == TaskStatus.Submitted,
            "Cannot refund"
        );

        task.status = TaskStatus.Refunded;

        pendingWithdrawals[task.requester] +=
            task.payment;

        emit TaskRefunded(
            taskId,
            task.payment
        );
    }

    function withdrawPayment() external {

        uint256 amount =
            pendingWithdrawals[msg.sender];

        require(
            amount > 0,
            "No payment available"
        );

        pendingWithdrawals[msg.sender] = 0;

        (bool success, ) =
            payable(msg.sender).call{
                value: amount
            }("");

        require(
            success,
            "Withdrawal failed"
        );

        emit PaymentWithdrawn(
            msg.sender,
            amount
        );
    }

    function getTask(
        uint256 taskId
    )
        external
        view
        taskExists(taskId)
        returns (Task memory)
    {
        return tasks[taskId];
    }

    function version()
        external
        pure
        returns (string memory)
    {
        return "0.1.0";
    }
}
