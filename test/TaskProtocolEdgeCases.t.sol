
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AgentRegistry} from "../contracts/AgentRegistry.sol";
import {TaskProtocol} from "../contracts/TaskProtocol.sol";

interface VmEdge {
    function prank(address sender) external;
    function deal(address who, uint256 amount) external;
    function warp(uint256 timestamp) external;
    function expectRevert() external;
}

contract TaskProtocolEdgeCasesTest {

    VmEdge private constant vm = VmEdge(
        address(uint160(uint256(
            keccak256("hevm cheat code")
        )))
    );

    AgentRegistry private registry;
    TaskProtocol private protocol;

    address private genesis = address(0x1001);
    address private atlas = address(0x1002);
    address private stranger = address(0x1003);

    uint256 private constant PAYMENT = 0.01 ether;
    uint256 private constant DURATION = 86400;

    function setUp() public {

        registry = new AgentRegistry();

        protocol = new TaskProtocol(
            address(registry)
        );

        vm.deal(genesis, 100 ether);
        vm.deal(atlas, 100 ether);
        vm.deal(stranger, 100 ether);

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
    }

    function createTask() internal {

        vm.prank(genesis);

        protocol.createTask{value: PAYMENT}(
            1,
            2,
            "Edge case test",
            DURATION
        );
    }

    function submitResult() internal {

        vm.prank(atlas);

        protocol.submitResult(
            1,
            "edge-case-result"
        );
    }

    function approveTask() internal {

        vm.prank(genesis);

        protocol.approveTask(1);
    }

    // EDGE CASE 01
    // Reject approval before result submission.

    function testApprovalBeforeSubmission()
        public
    {
        createTask();

        vm.expectRevert();

        vm.prank(genesis);

        protocol.approveTask(1);

        require(
            address(protocol).balance == PAYMENT,
            "Escrow balance changed"
        );
    }

    // EDGE CASE 02
    // Reject refund before task expiration.

    function testEarlyRefundRejected()
        public
    {
        createTask();

        vm.expectRevert();

        vm.prank(genesis);

        protocol.refundTask(1);

        require(
            address(protocol).balance == PAYMENT,
            "Early refund changed escrow"
        );
    }

    // EDGE CASE 03
    // Prevent repeated result submission.

    function testRepeatedSubmissionRejected()
        public
    {
        createTask();

        submitResult();

        vm.expectRevert();

        vm.prank(atlas);

        protocol.submitResult(
            1,
            "second-result"
        );

        require(
            address(protocol).balance == PAYMENT,
            "Unexpected escrow change"
        );
    }

    // EDGE CASE 04
    // Prevent repeated task approval.

    function testRepeatedApprovalRejected()
        public
    {
        createTask();

        submitResult();

        approveTask();

        vm.expectRevert();

        vm.prank(genesis);

        protocol.approveTask(1);

        uint256 balanceBefore = atlas.balance;

        vm.prank(atlas);

        protocol.withdrawPayment();

        require(
            atlas.balance == balanceBefore + PAYMENT,
            "Incorrect provider payment"
        );

        require(
            address(protocol).balance == 0,
            "Unexpected remaining funds"
        );
    }

    // EDGE CASE 05
    // Prevent refunds after completed settlement.

    function testRefundAfterCompletionRejected()
        public
    {
        createTask();

        submitResult();

        approveTask();

        vm.prank(atlas);

        protocol.withdrawPayment();

        vm.warp(
            block.timestamp + DURATION + 1
        );

        vm.expectRevert();

        vm.prank(genesis);

        protocol.refundTask(1);

        require(
            address(protocol).balance == 0,
            "Completed task balance changed"
        );
    }

    // EDGE CASE 06
    // Prevent unauthorized refunds.

    function testUnauthorizedRefundRejected()
        public
    {
        createTask();

        vm.warp(
            block.timestamp + DURATION + 1
        );

        vm.expectRevert();

        vm.prank(stranger);

        protocol.refundTask(1);

        require(
            address(protocol).balance == PAYMENT,
            "Unauthorized refund changed escrow"
        );

        uint256 balanceBefore = genesis.balance;

        vm.prank(genesis);

        protocol.refundTask(1);

        vm.prank(genesis);

        protocol.withdrawPayment();

        require(
            genesis.balance == balanceBefore + PAYMENT,
            "Requester refund incorrect"
        );

        require(
            address(protocol).balance == 0,
            "Refund did not clear escrow"
        );
    }

    // EDGE CASE 07
    // Investigate fund recovery after a submitted
    // task expires without requester approval.
    //
    // This test intentionally fails if neither
    // settlement nor refund remains possible.

    function testExpiredSubmittedTaskRecoverability()
        public
    {
        createTask();

        submitResult();

        vm.warp(
            block.timestamp + DURATION + 1
        );

        require(
            address(protocol).balance == PAYMENT,
            "Escrow deposit missing"
        );

        // Attempt settlement after expiration.

        vm.prank(genesis);

        (bool approvalSuccess, ) =
            address(protocol).call(
                abi.encodeWithSelector(
                    TaskProtocol.approveTask.selector,
                    uint256(1)
                )
            );

        if (approvalSuccess) {

            uint256 balanceBefore = atlas.balance;

            vm.prank(atlas);

            protocol.withdrawPayment();

            require(
                atlas.balance == balanceBefore + PAYMENT,
                "Provider recovery incorrect"
            );

            require(
                address(protocol).balance == 0,
                "Funds remain after settlement"
            );

            return;
        }

        // If approval is blocked, attempt refund.

        vm.prank(genesis);

        (bool refundSuccess, ) =
            address(protocol).call(
                abi.encodeWithSelector(
                    TaskProtocol.refundTask.selector,
                    uint256(1)
                )
            );

        if (refundSuccess) {

            uint256 balanceBefore = genesis.balance;

            vm.prank(genesis);

            protocol.withdrawPayment();

            require(
                genesis.balance == balanceBefore + PAYMENT,
                "Requester recovery incorrect"
            );

            require(
                address(protocol).balance == 0,
                "Funds remain after refund"
            );

            return;
        }

        // Neither recovery path was available.

        revert(
            "FUND LOCK RISK: expired submitted task cannot settle or refund"
        );
    }
}
