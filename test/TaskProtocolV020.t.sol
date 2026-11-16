// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {TaskProtocolV020} from "../contracts/TaskProtocolV020.sol";
import {AgentRegistry} from "../contracts/AgentRegistry.sol";

interface VmV020 {
    function prank(address) external;
    function deal(address, uint256) external;
    function warp(uint256) external;
    function expectRevert(bytes4) external;
}

contract TaskProtocolV020Test {
    VmV020 constant vm = VmV020(address(uint160(uint256(keccak256("hevm cheat code")))));
    TaskProtocolV020 p;
    address constant R = address(0xA11CE);
    address constant P = address(0xB0B);
    address constant A = address(0xCAFE);
    address constant X = address(0xDEAD);
    uint256 r; uint256 s;
    uint256 constant PAY = 1 ether;
    bytes32 constant HASH = keccak256("result bytes");
    bytes32 constant REASON = keccak256("incorrect result");

    function setUp() public {
        AgentRegistry registry = new AgentRegistry();
        vm.prank(R); registry.registerAgent("Genesis", "ipfs://genesis");
        vm.prank(P); registry.registerAgent("Atlas", "ipfs://atlas");
        r = 1; s = 2;
        p = new TaskProtocolV020(address(registry));
        vm.deal(R, 100 ether);
        vm.deal(P, 1 ether);
    }
    function create(uint256 duration, uint256 bps) internal returns (uint256) {
        vm.prank(R); return p.createTask{value: PAY}(r,s,"task",duration,A,bps);
    }
    function accept(uint256 id) internal { vm.prank(P); p.acceptTask(id); }
    function submit(uint256 id) internal { vm.prank(P); p.submitResult(id,"ipfs://result",HASH); }
    function dispute(uint256 id) internal { vm.prank(R); p.raiseDispute(id,REASON); }
    function delivered() internal returns (uint256 id) { id=create(1 days,5000); accept(id); submit(id); }
    function disputed() internal returns (uint256 id) { id=delivered(); dispute(id); }
    function status(uint256 id, TaskProtocolV020.TaskStatus expected) internal view {
        require(p.getTask(id).status==expected,"status mismatch");
    }
    function accounting(uint256 escrow, uint256 pending) internal view {
        require(p.totalEscrow()==escrow,"escrow mismatch");
        require(p.totalPendingWithdrawals()==pending,"pending mismatch");
        require(address(p).balance==escrow+pending,"balance mismatch");
        require(p.pendingWithdrawals(R)+p.pendingWithdrawals(P)==pending,"credit mismatch");
    }
    function testCancelBeforeAcceptance() public {
        uint256 id=create(1 days,5000); vm.prank(R); p.cancelTask(id);
        status(id,TaskProtocolV020.TaskStatus.Cancelled); accounting(0,PAY);
        require(p.pendingWithdrawals(R)==PAY,"refund mismatch");
    }
    function testCancelAfterAcceptanceReverts() public {
        uint256 id=create(1 days,5000); accept(id);
        vm.prank(R); vm.expectRevert(TaskProtocolV020.InvalidStatus.selector); p.cancelTask(id);
        accounting(PAY,0);
    }
    function testUnauthorizedAcceptance() public {
        uint256 id=create(1 days,5000);
        vm.prank(X); vm.expectRevert(TaskProtocolV020.Unauthorized.selector); p.acceptTask(id);
    }
    function testSubmitBeforeAcceptanceReverts() public {
        uint256 id=create(1 days,5000);
        vm.prank(P); vm.expectRevert(TaskProtocolV020.InvalidStatus.selector); p.submitResult(id,"ipfs://result",HASH);
    }
    function testAcceptAtDeadlineReverts() public {
        uint256 id=create(1 days,5000); vm.warp(p.getTask(id).deadline);
        vm.prank(P); vm.expectRevert(TaskProtocolV020.DeadlinePassed.selector); p.acceptTask(id);
    }
    function testSubmitAtDeadlineReverts() public {
        uint256 id=create(1 days,5000); accept(id); vm.warp(p.getTask(id).deadline);
        vm.prank(P); vm.expectRevert(TaskProtocolV020.DeadlinePassed.selector); p.submitResult(id,"ipfs://result",HASH);
    }
    function testUndeliveredRefundAtDeadline() public {
        uint256 id=create(1 days,5000); accept(id); vm.warp(p.getTask(id).deadline);
        vm.prank(X); p.refundTask(id); status(id,TaskProtocolV020.TaskStatus.Refunded);
        accounting(0,PAY); require(p.pendingWithdrawals(R)==PAY,"refund mismatch");
    }
    function testRefundBeforeDeadlineReverts() public {
        uint256 id=create(1 days,5000);
        vm.expectRevert(TaskProtocolV020.DeadlineNotReached.selector); p.refundTask(id);
    }
    function testLateDeliveryGetsFullReview() public {
        uint256 id=create(1 days,5000); accept(id); vm.warp(p.getTask(id).deadline-1); submit(id);
        TaskProtocolV020.Task memory t=p.getTask(id);
        require(t.reviewDeadline==block.timestamp+48 hours,"review mismatch");
        require(t.resultHash==HASH,"hash mismatch");
        vm.warp(t.deadline); vm.prank(R); p.approveTask(id);
        accounting(0,PAY); require(p.pendingWithdrawals(P)==PAY,"provider mismatch");
    }
    function testSubmittedCannotBeRefunded() public {
        uint256 id=delivered(); vm.warp(p.getTask(id).deadline);
        vm.prank(R); vm.expectRevert(TaskProtocolV020.InvalidStatus.selector); p.refundTask(id);
        accounting(PAY,0);
    }
    function testClaimBeforeReviewReverts() public {
        uint256 id=delivered(); vm.warp(p.getTask(id).reviewDeadline-1);
        vm.expectRevert(TaskProtocolV020.DeadlineNotReached.selector); p.claimPayment(id);
    }
    function testClaimAtReviewDeadline() public {
        uint256 id=delivered(); vm.warp(p.getTask(id).reviewDeadline);
        vm.prank(X); p.claimPayment(id); status(id,TaskProtocolV020.TaskStatus.Completed);
        accounting(0,PAY); require(p.pendingWithdrawals(P)==PAY,"provider mismatch");
        vm.expectRevert(TaskProtocolV020.InvalidStatus.selector); p.claimPayment(id);
    }
    function testDisputeAtReviewDeadlineReverts() public {
        uint256 id=delivered(); vm.warp(p.getTask(id).reviewDeadline);
        vm.prank(R); vm.expectRevert(TaskProtocolV020.DeadlinePassed.selector); p.raiseDispute(id,REASON);
    }
    function testDisputeLocksFunds() public {
        uint256 id=disputed(); status(id,TaskProtocolV020.TaskStatus.Disputed); accounting(PAY,0);
        vm.warp(p.getTask(id).reviewDeadline);
        vm.expectRevert(TaskProtocolV020.InvalidStatus.selector); p.claimPayment(id);
        vm.expectRevert(TaskProtocolV020.InvalidStatus.selector); p.refundTask(id);
    }
    function testUnauthorizedArbitration() public {
        uint256 id=disputed(); vm.prank(X); vm.expectRevert(TaskProtocolV020.Unauthorized.selector); p.resolveDispute(id,PAY);
    }
    function testArbitratorSplit() public {
        uint256 id=disputed(); vm.prank(A); p.resolveDispute(id,0.7 ether);
        status(id,TaskProtocolV020.TaskStatus.Settled); accounting(0,PAY);
        require(p.pendingWithdrawals(P)==0.7 ether,"provider mismatch");
        require(p.pendingWithdrawals(R)==0.3 ether,"requester mismatch");
    }
    function testArbitratorCannotOverallocate() public {
        uint256 id=disputed(); vm.prank(A); vm.expectRevert(TaskProtocolV020.InvalidAllocation.selector); p.resolveDispute(id,PAY+1);
    }
    function testMutualSettlement() public {
        uint256 id=disputed(); vm.prank(R); p.proposeSettlement(id,0.4 ether);
        vm.prank(P); p.acceptSettlement(id,0.4 ether); accounting(0,PAY);
        require(p.pendingWithdrawals(P)==0.4 ether,"provider mismatch");
    }
    function testCannotAcceptOwnOffer() public {
        uint256 id=disputed(); vm.prank(R); p.proposeSettlement(id,0.4 ether);
        vm.prank(R); vm.expectRevert(TaskProtocolV020.Unauthorized.selector); p.acceptSettlement(id,0.4 ether);
    }
    function testTimeoutBeforeDeadlineReverts() public {
        uint256 id=disputed(); vm.expectRevert(TaskProtocolV020.DeadlineNotReached.selector); p.finalizeDisputeTimeout(id);
    }
    function testTimeoutAtDeadline() public {
        uint256 id=disputed(); vm.warp(p.getTask(id).disputeDeadline);
        vm.prank(A); vm.expectRevert(TaskProtocolV020.DeadlinePassed.selector); p.resolveDispute(id,PAY);
        vm.prank(X); p.finalizeDisputeTimeout(id); accounting(0,PAY);
        require(p.pendingWithdrawals(P)==PAY/2 && p.pendingWithdrawals(R)==PAY/2,"split mismatch");
    }
    function testWithdrawalAndDoubleWithdrawal() public {
        uint256 id=delivered(); vm.prank(R); p.approveTask(id);
        uint256 beforeBalance=P.balance; vm.prank(P); p.withdrawPayment();
        require(P.balance==beforeBalance+PAY,"withdraw mismatch"); accounting(0,0);
        vm.prank(P); vm.expectRevert(TaskProtocolV020.NoPaymentAvailable.selector); p.withdrawPayment();
    }
    function testFuzzTimeoutAllocation(uint16 raw) public {
        uint256 bps=uint256(raw)%10001;
        uint256 id=create(1 days,bps); accept(id); submit(id); dispute(id);
        vm.warp(p.getTask(id).disputeDeadline); p.finalizeDisputeTimeout(id);
        accounting(0,PAY); require(p.pendingWithdrawals(P)==PAY*bps/10000,"allocation mismatch");
    }
}
