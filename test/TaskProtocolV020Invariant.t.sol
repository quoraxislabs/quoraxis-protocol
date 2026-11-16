// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TaskProtocolV020} from "../contracts/TaskProtocolV020.sol";
import {AgentRegistry} from "../contracts/AgentRegistry.sol";

interface VmInvariantV020 {
    function prank(address) external;
    function deal(address, uint256) external;
    function warp(uint256) external;
}

contract V020SettlementHandler {
    VmInvariantV020 private constant vm = VmInvariantV020(address(uint160(uint256(keccak256("hevm cheat code")))));
    TaskProtocolV020 public immutable p;
    address public constant R = address(0xA11CE);
    address public constant P = address(0xB0B);
    address public constant A = address(0xCAFE);
    uint256 public deposited;
    uint256 public withdrawn;
    uint256 public expectedRequester;
    uint256 public expectedProvider;
    uint256 public unexpectedFailures;
    uint256 public successfulActions;
    mapping(uint256 => uint256) public originalPayment;
    mapping(uint256 => bool) public settled;

    constructor(TaskProtocolV020 protocol) { p = protocol; }

    function _call(address actor, bytes memory data, uint256 value) internal returns (bool ok) {
        vm.prank(actor);
        (ok,) = address(p).call{value: value}(data);
        if (ok) successfulActions++;
        else unexpectedFailures++;
    }

    function _id(uint256 seed) internal view returns (uint256) {
        uint256 n = p.taskCount();
        return n == 0 ? 0 : seed % n + 1;
    }

    function _credit(uint256 id, uint256 providerAmount) internal {
        if (settled[id] || providerAmount > originalPayment[id]) { unexpectedFailures++; return; }
        settled[id] = true;
        expectedProvider += providerAmount;
        expectedRequester += originalPayment[id] - providerAmount;
    }

    function create(uint256 seed, uint256 duration, uint256 bps) external {
        uint256 amount = seed % 1 ether + 1;
        uint256 id = p.taskCount() + 1;
        if (_call(R, abi.encodeCall(p.createTask, (1, 2, "invariant task", duration % 30 days + 1, A, bps % 10001)), amount)) {
            deposited += amount;
            originalPayment[id] = amount;
        }
    }

    function advanceTime(uint256 seed) external { vm.warp(block.timestamp + seed % 8 days + 1); }

    function accept(uint256 seed) external {
        uint256 id = _id(seed); if (id == 0) return;
        TaskProtocolV020.Task memory t = p.getTask(id);
        if (t.status != TaskProtocolV020.TaskStatus.Created || block.timestamp >= t.deadline) return;
        _call(P, abi.encodeCall(p.acceptTask, (id)), 0);
    }

    function cancel(uint256 seed) external {
        uint256 id = _id(seed); if (id == 0) return;
        if (p.getTask(id).status != TaskProtocolV020.TaskStatus.Created) return;
        if (_call(R, abi.encodeCall(p.cancelTask, (id)), 0)) _credit(id, 0);
    }

    function submit(uint256 seed) external {
        uint256 id = _id(seed); if (id == 0) return;
        TaskProtocolV020.Task memory t = p.getTask(id);
        if (t.status != TaskProtocolV020.TaskStatus.Accepted || block.timestamp >= t.deadline) return;
        _call(P, abi.encodeCall(p.submitResult, (id, "ipfs://result", keccak256("result"))), 0);
    }

    function approve(uint256 seed) external {
        uint256 id = _id(seed); if (id == 0) return;
        if (p.getTask(id).status != TaskProtocolV020.TaskStatus.Submitted) return;
        if (_call(R, abi.encodeCall(p.approveTask, (id)), 0)) _credit(id, originalPayment[id]);
    }

    function claim(uint256 seed) external {
        uint256 id = _id(seed); if (id == 0) return;
        TaskProtocolV020.Task memory t = p.getTask(id);
        if (t.status != TaskProtocolV020.TaskStatus.Submitted || block.timestamp < t.reviewDeadline) return;
        if (_call(P, abi.encodeCall(p.claimPayment, (id)), 0)) _credit(id, originalPayment[id]);
    }

    function refund(uint256 seed) external {
        uint256 id = _id(seed); if (id == 0) return;
        TaskProtocolV020.Task memory t = p.getTask(id);
        if ((t.status != TaskProtocolV020.TaskStatus.Created && t.status != TaskProtocolV020.TaskStatus.Accepted) || block.timestamp < t.deadline) return;
        if (_call(R, abi.encodeCall(p.refundTask, (id)), 0)) _credit(id, 0);
    }

    function dispute(uint256 seed) external {
        uint256 id = _id(seed); if (id == 0) return;
        TaskProtocolV020.Task memory t = p.getTask(id);
        if (t.status != TaskProtocolV020.TaskStatus.Submitted || block.timestamp >= t.reviewDeadline) return;
        _call(R, abi.encodeCall(p.raiseDispute, (id, keccak256("reason"))), 0);
    }

    function arbitrate(uint256 seed, uint256 raw) external {
        uint256 id = _id(seed); if (id == 0) return;
        TaskProtocolV020.Task memory t = p.getTask(id);
        if (t.status != TaskProtocolV020.TaskStatus.Disputed || block.timestamp >= t.disputeDeadline) return;
        uint256 amount = raw % (originalPayment[id] + 1);
        if (_call(A, abi.encodeCall(p.resolveDispute, (id, amount)), 0)) _credit(id, amount);
    }

    function mutual(uint256 seed, uint256 raw, bool providerProposes) external {
        uint256 id = _id(seed); if (id == 0) return;
        TaskProtocolV020.Task memory t = p.getTask(id);
        if (t.status != TaskProtocolV020.TaskStatus.Disputed || block.timestamp >= t.disputeDeadline) return;
        uint256 amount = raw % (originalPayment[id] + 1);
        if (!_call(providerProposes ? P : R, abi.encodeCall(p.proposeSettlement, (id, amount)), 0)) return;
        if (_call(providerProposes ? R : P, abi.encodeCall(p.acceptSettlement, (id, amount)), 0)) _credit(id, amount);
    }

    function timeout(uint256 seed) external {
        uint256 id = _id(seed); if (id == 0) return;
        TaskProtocolV020.Task memory t = p.getTask(id);
        if (t.status != TaskProtocolV020.TaskStatus.Disputed || block.timestamp < t.disputeDeadline) return;
        uint256 amount = originalPayment[id] * t.timeoutProviderBps / 10000;
        if (_call(R, abi.encodeCall(p.finalizeDisputeTimeout, (id)), 0)) _credit(id, amount);
    }

    function withdraw(bool provider) external {
        address actor = provider ? P : R;
        uint256 amount = p.pendingWithdrawals(actor);
        if (amount == 0) return;
        uint256 beforeBalance = actor.balance;
        if (_call(actor, abi.encodeCall(p.withdrawPayment, ()), 0)) {
            if (actor.balance != beforeBalance + amount) unexpectedFailures++;
            withdrawn += amount;
            if (provider) {
                if (amount > expectedProvider) unexpectedFailures++;
                else expectedProvider -= amount;
            } else {
                if (amount > expectedRequester) unexpectedFailures++;
                else expectedRequester -= amount;
            }
        }
    }
}

contract TaskProtocolV020InvariantTest {
    VmInvariantV020 private constant vm = VmInvariantV020(address(uint160(uint256(keccak256("hevm cheat code")))));
    TaskProtocolV020 private p;
    V020SettlementHandler private h;
    address private constant R = address(0xA11CE);
    address private constant P = address(0xB0B);
    struct FuzzSelector { address addr; bytes4[] selectors; }

    function setUp() public {
        AgentRegistry registry = new AgentRegistry();
        vm.prank(R); registry.registerAgent("Genesis", "ipfs://genesis");
        vm.prank(P); registry.registerAgent("Atlas", "ipfs://atlas");
        p = new TaskProtocolV020(address(registry));
        h = new V020SettlementHandler(p);
        vm.deal(R, 10000 ether);
        vm.deal(P, 10000 ether);
        // Seed distinct lifecycle branches so random sequences can exercise them.
        h.create(1 ether - 1, 30 days - 1, 5000);
        h.create(1 ether - 1, 30 days - 1, 2500); h.accept(1);
        h.create(1 ether - 1, 30 days - 1, 7500); h.accept(2); h.submit(2);
        h.create(1 ether - 1, 30 days - 1, 5000); h.accept(3); h.submit(3); h.dispute(3);
    }

    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1); targets[0] = address(h);
    }

    function targetSelectors() public view returns (FuzzSelector[] memory targets) {
        bytes4[] memory s = new bytes4[](13);
        s[0] = h.create.selector; s[1] = h.advanceTime.selector;
        s[2] = h.accept.selector; s[3] = h.cancel.selector;
        s[4] = h.submit.selector; s[5] = h.approve.selector;
        s[6] = h.claim.selector; s[7] = h.refund.selector;
        s[8] = h.dispute.selector; s[9] = h.arbitrate.selector;
        s[10] = h.mutual.selector; s[11] = h.timeout.selector;
        s[12] = h.withdraw.selector;
        targets = new FuzzSelector[](1); targets[0] = FuzzSelector(address(h), s);
    }

    function invariant_FundsAndLifecycle() public view {
        uint256 escrow;
        uint256 terminal;
        for (uint256 id = 1; id <= p.taskCount(); id++) {
            TaskProtocolV020.Task memory t = p.getTask(id);
            require(t.payment == h.originalPayment(id) && t.payment > 0, "payment changed");
            bool live = t.status == TaskProtocolV020.TaskStatus.Created ||
                t.status == TaskProtocolV020.TaskStatus.Accepted ||
                t.status == TaskProtocolV020.TaskStatus.Submitted ||
                t.status == TaskProtocolV020.TaskStatus.Disputed;
            require(h.settled(id) != live, "lifecycle mismatch");
            if (live) escrow += t.payment;
            else terminal += t.payment;
        }
        require(escrow == p.totalEscrow(), "escrow mismatch");
        require(p.pendingWithdrawals(R) == h.expectedRequester(), "requester credit mismatch");
        require(p.pendingWithdrawals(P) == h.expectedProvider(), "provider credit mismatch");
        uint256 pending = h.expectedRequester() + h.expectedProvider();
        require(pending == p.totalPendingWithdrawals(), "pending mismatch");
        require(terminal == pending + h.withdrawn(), "terminal funds mismatch");
        require(escrow + terminal == h.deposited(), "deposit mismatch");
        require(address(p).balance == escrow + pending, "balance mismatch");
        require(address(p).balance + h.withdrawn() == h.deposited(), "fund conservation");
        require(h.unexpectedFailures() == 0, "unexpected valid action failure");
    }
}
