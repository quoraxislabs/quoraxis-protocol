
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TaskProtocolV020} from "../contracts/TaskProtocolV020.sol";
import {AgentRegistry} from "../contracts/AgentRegistry.sol";

interface VmV020Attack {
    function prank(address) external;
    function deal(address, uint256) external;
    function expectRevert(bytes4) external;
}

contract V020MaliciousReceiver {
    TaskProtocolV020 immutable p;

    bool public rejectETH;
    bool public attack;
    bool public attempted;
    bool public reentrySucceeded;

    constructor(TaskProtocolV020 protocol) {
        p = protocol;
    }

    function configure(bool reject_, bool attack_) external {
        rejectETH = reject_;
        attack = attack_;
    }

    function withdraw() external {
        p.withdrawPayment();
    }

    function redirect(address payable recipient) external {
        p.withdrawPaymentTo(recipient);
    }

    receive() external payable {
        if (rejectETH) {
            revert("receiver rejects ETH");
        }

        if (attack && !attempted) {
            attempted = true;

            (reentrySucceeded, ) = address(p).call(
                abi.encodeWithSelector(
                    p.withdrawPayment.selector
                )
            );
        }
    }
}

contract TaskProtocolV020AttackTest {
    VmV020Attack constant vm = VmV020Attack(
        address(uint160(uint256(keccak256("hevm cheat code"))))
    );

    TaskProtocolV020 p;
    V020MaliciousReceiver receiver;

    address constant R = address(0xA11CE);
    address constant A = address(0xCAFE);
    address constant X = address(0xDEAD);

    uint256 constant PAY = 1 ether;

    function setUp() public {
        AgentRegistry registry = new AgentRegistry();

        p = new TaskProtocolV020(address(registry));

        receiver = new V020MaliciousReceiver(p);

        vm.prank(R);
        registry.registerAgent(
            "Requester",
            "ipfs://r"
        );

        vm.prank(address(receiver));
        registry.registerAgent(
            "Provider",
            "ipfs://p"
        );

        vm.deal(R, 100 ether);
    }

    function delivered() internal returns (uint256 id) {
        vm.prank(R);

        id = p.createTask{value: PAY}(
            1,
            2,
            "task",
            1 days,
            A,
            5000
        );

        vm.prank(address(receiver));
        p.acceptTask(id);

        vm.prank(address(receiver));
        p.submitResult(
            id,
            "ipfs://result",
            keccak256("result")
        );
    }

    function approved() internal returns (uint256 id) {
        id = delivered();

        vm.prank(R);
        p.approveTask(id);
    }

    function disputed() internal returns (uint256 id) {
        id = delivered();

        vm.prank(R);
        p.raiseDispute(
            id,
            keccak256("reason")
        );
    }

    function check(
        uint256 escrow,
        uint256 pending
    ) internal view {
        require(
            p.totalEscrow() == escrow,
            "escrow"
        );

        require(
            p.totalPendingWithdrawals() == pending,
            "pending"
        );

        require(
            address(p).balance == escrow + pending,
            "balance"
        );

        require(
            p.pendingWithdrawals(R) +
            p.pendingWithdrawals(address(receiver))
            == pending,
            "credits"
        );
    }

    function testReentrantWithdrawalCannotStealOtherEscrow()
        public
    {
        approved();
        delivered();

        receiver.configure(false, true);
        receiver.withdraw();

        require(
            receiver.attempted(),
            "callback not executed"
        );

        require(
            !receiver.reentrySucceeded(),
            "reentry succeeded"
        );

        require(
            address(receiver).balance == PAY,
            "overpayment"
        );

        require(
            p.pendingWithdrawals(address(receiver)) == 0,
            "credit remains"
        );

        check(PAY, 0);
    }

    function testRejectingReceiverPreservesCreditAndAllowsRedirect()
        public
    {
        approved();

        receiver.configure(true, false);

        vm.expectRevert(
            TaskProtocolV020.WithdrawalFailed.selector
        );

        receiver.withdraw();

        check(0, PAY);

        require(
            p.pendingWithdrawals(address(receiver)) == PAY,
            "lost credit"
        );

        uint256 beforeBalance = X.balance;

        receiver.redirect(payable(X));

        require(
            X.balance == beforeBalance + PAY,
            "redirect failed"
        );

        check(0, 0);
    }

    function testRejectingReceiverCannotBlockOtherWithdrawal()
        public
    {
        uint256 id = disputed();

        vm.prank(A);
        p.resolveDispute(id, PAY / 2);

        receiver.configure(true, false);

        vm.expectRevert(
            TaskProtocolV020.WithdrawalFailed.selector
        );

        receiver.withdraw();

        uint256 beforeBalance = R.balance;

        vm.prank(R);
        p.withdrawPayment();

        require(
            R.balance == beforeBalance + PAY / 2,
            "requester blocked"
        );

        check(0, PAY / 2);

        require(
            p.pendingWithdrawals(address(receiver)) == PAY / 2,
            "provider credit lost"
        );
    }

    function testArbitratorCannotSettleUndisputedTask()
        public
    {
        uint256 id = delivered();

        vm.prank(A);

        vm.expectRevert(
            TaskProtocolV020.InvalidStatus.selector
        );

        p.resolveDispute(id, PAY);

        check(PAY, 0);
    }

    function testArbitratorCannotSettleTwice()
        public
    {
        uint256 id = disputed();

        vm.prank(A);
        p.resolveDispute(id, PAY / 2);

        vm.prank(A);

        vm.expectRevert(
            TaskProtocolV020.InvalidStatus.selector
        );

        p.resolveDispute(id, PAY);

        check(0, PAY);

        require(
            p.pendingWithdrawals(R) == PAY / 2,
            "requester allocation changed"
        );

        require(
            p.pendingWithdrawals(address(receiver)) == PAY / 2,
            "provider allocation changed"
        );
    }

    function testStaleSettlementOfferCannotBeAccepted()
        public
    {
        uint256 id = disputed();

        vm.prank(R);
        p.proposeSettlement(id, PAY / 4);

        vm.prank(R);
        p.proposeSettlement(id, PAY / 2);

        vm.prank(address(receiver));

        vm.expectRevert(
            TaskProtocolV020.InvalidAllocation.selector
        );

        p.acceptSettlement(id, PAY / 4);

        check(PAY, 0);

        vm.prank(address(receiver));
        p.acceptSettlement(id, PAY / 2);

        check(0, PAY);
    }

    function testThirdPartyCannotRedirectAnotherCredit()
        public
    {
        approved();

        vm.prank(X);

        vm.expectRevert(
            TaskProtocolV020.NoPaymentAvailable.selector
        );

        p.withdrawPaymentTo(payable(X));

        require(
            p.pendingWithdrawals(address(receiver)) == PAY,
            "credit stolen"
        );

        check(0, PAY);
    }
}
