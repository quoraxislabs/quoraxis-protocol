
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../contracts/AgentRegistry.sol";
import "../contracts/TaskProtocol.sol";

interface VmTask {
    function prank(address sender) external;
    function deal(address who, uint256 amount) external;
    function warp(uint256 timestamp) external;
    function expectRevert(bytes calldata reason) external;
}

contract TaskProtocolTest {

    VmTask private constant vm = VmTask(
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

    string private constant RESULT_URI =
        "https://quoraxislabs.github.io/";

    function setUp() public {

        registry = new AgentRegistry();

        protocol = new TaskProtocol(address(registry));

        vm.deal(genesis, 10 ether);
        vm.deal(atlas, 10 ether);
        vm.deal(stranger, 10 ether);

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

    function createSampleTask() internal {

        vm.prank(genesis);

        protocol.createTask{value: PAYMENT}(
            1,
            2,
            "Verify sample dataset",
            DURATION
        );
    }

    function submitSampleResult() internal {

        vm.prank(atlas);

        protocol.submitResult(
            1,
            RESULT_URI
        );
    }

    function approveSampleTask() internal {

        vm.prank(genesis);

        protocol.approveTask(1);
    }

    // TEST 01
    // Complete task settlement lifecycle

    function testCompleteTaskLifecycle() public {

        uint256 initialBalance = atlas.balance;

        createSampleTask();

        require(
            address(protocol).balance == PAYMENT,
            "Incorrect escrow balance"
        );

        submitSampleResult();

        approveSampleTask();

        vm.prank(atlas);

        protocol.withdrawPayment();

        require(
            atlas.balance == initialBalance + PAYMENT,
            "Provider payment incorrect"
        );

        require(
            address(protocol).balance == 0,
            "Escrow not cleared"
        );
    }

    // TEST 02
    // Prevent double payment withdrawal

    function testDoubleWithdrawalRejected() public {

        createSampleTask();
        submitSampleResult();
        approveSampleTask();

        vm.prank(atlas);

        protocol.withdrawPayment();

        vm.expectRevert(
            bytes("No payment available")
        );

        vm.prank(atlas);

        protocol.withdrawPayment();
    }

    // TEST 03
    // Reject unauthorized task approval

    function testUnauthorizedApproval() public {

        createSampleTask();
        submitSampleResult();

        vm.expectRevert(
            bytes("Not task requester")
        );

        vm.prank(atlas);

        protocol.approveTask(1);
    }

    // TEST 04
    // Reject nonexistent provider

    function testNonexistentProvider() public {

        vm.expectRevert(
            bytes("Agent does not exist")
        );

        vm.prank(genesis);

        protocol.createTask{value: PAYMENT}(
            1,
            999,
            "Invalid provider test",
            DURATION
        );

        require(
            address(protocol).balance == 0,
            "Unexpected escrow deposit"
        );
    }

    // TEST 05
    // Reject zero-payment tasks

    function testZeroPaymentRejected() public {

        vm.expectRevert(
            bytes("Payment required")
        );

        vm.prank(genesis);

        protocol.createTask(
            1,
            2,
            "Zero payment test",
            DURATION
        );
    }

    // TEST 06
    // Refund expired task and withdraw funds

    function testExpiredTaskRefund() public {

        uint256 initialBalance = genesis.balance;

        vm.prank(genesis);

        protocol.createTask{value: PAYMENT}(
            1,
            2,
            "Refund test",
            60
        );

        require(
            address(protocol).balance == PAYMENT,
            "Escrow deposit missing"
        );

        vm.warp(block.timestamp + 61);

        vm.prank(genesis);

        protocol.refundTask(1);

        vm.prank(genesis);

        protocol.withdrawPayment();

        require(
            genesis.balance == initialBalance,
            "Refund amount incorrect"
        );

        require(
            address(protocol).balance == 0,
            "Refund did not clear escrow"
        );
    }

    // TEST 07
    // Reject unauthorized result submission

    function testUnauthorizedSubmission() public {

        createSampleTask();

        vm.expectRevert(
            bytes("Not task provider")
        );

        vm.prank(genesis);

        protocol.submitResult(
            1,
            RESULT_URI
        );
    }

    // TEST 08
    // Reject third-party result submission

    function testThirdPartySubmission() public {

        createSampleTask();

        vm.expectRevert(
            bytes("Not task provider")
        );

        vm.prank(stranger);

        protocol.submitResult(
            1,
            RESULT_URI
        );
    }
}
