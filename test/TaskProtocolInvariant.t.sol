
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../contracts/AgentRegistry.sol";
import "../contracts/TaskProtocol.sol";

interface VmInvariant {
    function prank(address sender) external;
    function deal(address who, uint256 amount) external;
    function warp(uint256 timestamp) external;
}

contract TaskProtocolHandler {

    VmInvariant private constant vm = VmInvariant(
        address(uint160(uint256(
            keccak256("hevm cheat code")
        )))
    );

    TaskProtocol public immutable protocol;

    address public immutable genesis;
    address public immutable atlas;

    uint256 public totalDeposited;
    uint256 public totalWithdrawn;

    uint256 public activeEscrow;
    uint256 public pendingGenesis;
    uint256 public pendingAtlas;

    uint256 public taskCount;

    enum Status {
        Created,
        Submitted,
        Completed,
        Refunded
    }

    struct TaskRecord {
        uint256 amount;
        uint256 deadline;
        Status status;
    }

    mapping(uint256 => TaskRecord) public records;

    constructor(
        TaskProtocol _protocol,
        address _genesis,
        address _atlas
    ) {
        protocol = _protocol;
        genesis = _genesis;
        atlas = _atlas;
    }

    // Create tasks using variable escrow amounts.

    function createTask(
        uint256 rawAmount
    ) external {

        uint256 amount =
            (rawAmount % 1 ether) + 1;

        if (genesis.balance < amount) {
            return;
        }

        vm.prank(genesis);

        protocol.createTask{value: amount}(
            1,
            2,
            "Invariant test task",
            86400
        );

        taskCount++;

        records[taskCount] = TaskRecord({
            amount: amount,
            deadline: block.timestamp + 86400,
            status: Status.Created
        });

        totalDeposited += amount;
        activeEscrow += amount;
    }

    // Submit a result for an existing task.

    function submitResult(
        uint256 seed
    ) external {

        if (taskCount == 0) {
            return;
        }

        uint256 id =
            (seed % taskCount) + 1;

        TaskRecord storage record =
            records[id];

        if (record.status != Status.Created) {
            return;
        }

        if (block.timestamp >= record.deadline) {
            return;
        }

        vm.prank(atlas);

        protocol.submitResult(
            id,
            "invariant-result"
        );

        record.status = Status.Submitted;
    }

    // Approve a submitted task.

    function approveTask(
        uint256 seed
    ) external {

        if (taskCount == 0) {
            return;
        }

        uint256 id =
            (seed % taskCount) + 1;

        TaskRecord storage record =
            records[id];

        if (record.status != Status.Submitted) {
            return;
        }

        if (block.timestamp >= record.deadline) {
            return;
        }

        vm.prank(genesis);

        protocol.approveTask(id);

        record.status = Status.Completed;

        activeEscrow -= record.amount;

        pendingAtlas += record.amount;
    }

    // Refund an expired, unsubmitted task.

    function refundTask(
        uint256 seed
    ) external {

        if (taskCount == 0) {
            return;
        }

        uint256 id =
            (seed % taskCount) + 1;

        TaskRecord storage record =
            records[id];

        if (record.status != Status.Created) {
            return;
        }

        if (block.timestamp <= record.deadline) {
            return;
        }

        vm.prank(genesis);

        protocol.refundTask(id);

        record.status = Status.Refunded;

        activeEscrow -= record.amount;

        pendingGenesis += record.amount;
    }

    // Withdraw approved provider payments.

    function withdrawProvider() external {

        uint256 amount = pendingAtlas;

        if (amount == 0) {
            return;
        }

        uint256 balanceBefore = atlas.balance;

        vm.prank(atlas);

        protocol.withdrawPayment();

        require(
            atlas.balance == balanceBefore + amount,
            "Incorrect provider withdrawal"
        );

        pendingAtlas = 0;

        totalWithdrawn += amount;
    }

    // Withdraw requester refunds.

    function withdrawRequester() external {

        uint256 amount = pendingGenesis;

        if (amount == 0) {
            return;
        }

        uint256 balanceBefore = genesis.balance;

        vm.prank(genesis);

        protocol.withdrawPayment();

        require(
            genesis.balance == balanceBefore + amount,
            "Incorrect requester withdrawal"
        );

        pendingGenesis = 0;

        totalWithdrawn += amount;
    }

    // Advance time to exercise task expiration.

    function advanceTime(
        uint256 rawSeconds
    ) external {

        uint256 elapsed =
            (rawSeconds % 172800) + 1;

        vm.warp(
            block.timestamp + elapsed
        );
    }
}

contract TaskProtocolInvariantTest {

    VmInvariant private constant vm = VmInvariant(
        address(uint160(uint256(
            keccak256("hevm cheat code")
        )))
    );

    AgentRegistry private registry;
    TaskProtocol private protocol;

    TaskProtocolHandler private handler;

    address private genesis = address(0x1001);
    address private atlas = address(0x1002);

    uint256 private constant INITIAL_BALANCE =
        1000 ether;

    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    function setUp() public {

        registry = new AgentRegistry();

        protocol = new TaskProtocol(
            address(registry)
        );

        vm.deal(genesis, INITIAL_BALANCE);

        vm.deal(atlas, INITIAL_BALANCE);

        vm.prank(genesis);

        registry.registerAgent(
            "Genesis",
            "genesis-metadata"
        );

        vm.prank(atlas);

        registry.registerAgent(
            "Atlas",
            "atlas-metadata"
        );

        handler = new TaskProtocolHandler(
            protocol,
            genesis,
            atlas
        );
    }

    // Restrict invariant fuzzing to the handler.

    function targetContracts()
        public
        view
        returns (address[] memory targets)
    {
        targets = new address[](1);

        targets[0] = address(handler);
    }

    // Select the supported state-changing actions.

    function targetSelectors()
        public
        view
        returns (FuzzSelector[] memory targets)
    {
        bytes4[] memory selectors =
            new bytes4[](7);

        selectors[0] =
            TaskProtocolHandler.createTask.selector;

        selectors[1] =
            TaskProtocolHandler.submitResult.selector;

        selectors[2] =
            TaskProtocolHandler.approveTask.selector;

        selectors[3] =
            TaskProtocolHandler.refundTask.selector;

        selectors[4] =
            TaskProtocolHandler.withdrawProvider.selector;

        selectors[5] =
            TaskProtocolHandler.withdrawRequester.selector;

        selectors[6] =
            TaskProtocolHandler.advanceTime.selector;

        targets = new FuzzSelector[](1);

        targets[0] = FuzzSelector({
            addr: address(handler),
            selectors: selectors
        });
    }

    // INVARIANT 01
    // Contract balance must cover all tracked liabilities.

    function invariant_EscrowAccounting()
        public
        view
    {
        uint256 liabilities =
            handler.activeEscrow() +
            handler.pendingGenesis() +
            handler.pendingAtlas();

        require(
            address(protocol).balance == liabilities,
            "Escrow accounting mismatch"
        );
    }

    // INVARIANT 02
    // Deposits must equal withdrawals plus remaining funds.

    function invariant_DepositConservation()
        public
        view
    {
        require(
            handler.totalDeposited() ==
            handler.totalWithdrawn() +
            address(protocol).balance,
            "Deposit conservation violated"
        );
    }

    // INVARIANT 03
    // Total ETH across both agents and the protocol
    // must remain constant.

    function invariant_TotalFundsConserved()
        public
        view
    {
        uint256 total =
            genesis.balance +
            atlas.balance +
            address(protocol).balance;

        require(
            total == INITIAL_BALANCE * 2,
            "Total funds not conserved"
        );
    }

    // INVARIANT 04
    // Withdrawals must never exceed deposits.

    function invariant_NoOverWithdrawal()
        public
        view
    {
        require(
            handler.totalWithdrawn() <=
            handler.totalDeposited(),
            "Withdrawals exceed deposits"
        );
    }
}
