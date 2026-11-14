
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../contracts/AgentRegistry.sol";
import "../contracts/TaskProtocol.sol";

interface VmFuzz {
    function prank(address sender) external;
    function deal(address who, uint256 amount) external;
    function warp(uint256 timestamp) external;
    function expectRevert(bytes calldata reason) external;
}

contract TaskProtocolFuzzTest {

    VmFuzz private constant vm = VmFuzz(
        address(uint160(uint256(
            keccak256("hevm cheat code")
        )))
    );

    AgentRegistry private registry;
    TaskProtocol private protocol;

    address private genesis = address(0x1001);
    address private atlas = address(0x1002);

    uint256 private constant MAX_PAYMENT = 100 ether;
    uint256 private constant DURATION = 86400;

    function setUp() public {

        registry = new AgentRegistry();

        protocol = new TaskProtocol(address(registry));

        vm.deal(genesis, 1000 ether);
        vm.deal(atlas, 1000 ether);

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

    function boundPayment(
        uint256 amount
    ) internal pure returns (uint256) {

        return (amount % MAX_PAYMENT) + 1;
    }

    // FUZZ TEST 01
    // Verify correct settlement for variable payments

    function testFuzzSettlement(
        uint256 rawAmount
    ) public {

        uint256 amount = boundPayment(rawAmount);

        uint256 initialBalance = atlas.balance;

        vm.prank(genesis);

        protocol.createTask{value: amount}(
            1,
            2,
            "Fuzz settlement test",
            DURATION
        );

        require(
            address(protocol).balance == amount,
            "Incorrect escrow amount"
        );

        vm.prank(atlas);

        protocol.submitResult(
            1,
            "fuzz-result"
        );

        vm.prank(genesis);

        protocol.approveTask(1);

        vm.prank(atlas);

        protocol.withdrawPayment();

        require(
            atlas.balance == initialBalance + amount,
            "Incorrect provider payment"
        );

        require(
            address(protocol).balance == 0,
            "Escrow not cleared"
        );
    }

    // FUZZ TEST 02
    // Verify correct refunds for variable payments

    function testFuzzRefund(
        uint256 rawAmount
    ) public {

        uint256 amount = boundPayment(rawAmount);

        uint256 initialBalance = genesis.balance;

        vm.prank(genesis);

        protocol.createTask{value: amount}(
            1,
            2,
            "Fuzz refund test",
            60
        );

        require(
            address(protocol).balance == amount,
            "Incorrect escrow deposit"
        );

        vm.warp(block.timestamp + 61);

        vm.prank(genesis);

        protocol.refundTask(1);

        vm.prank(genesis);

        protocol.withdrawPayment();

        require(
            genesis.balance == initialBalance,
            "Incorrect refund amount"
        );

        require(
            address(protocol).balance == 0,
            "Refund did not clear escrow"
        );
    }

    // FUZZ TEST 03
    // Prevent duplicate withdrawal at any payment amount

    function testFuzzDoubleWithdrawal(
        uint256 rawAmount
    ) public {

        uint256 amount = boundPayment(rawAmount);

        vm.prank(genesis);

        protocol.createTask{value: amount}(
            1,
            2,
            "Fuzz withdrawal test",
            DURATION
        );

        vm.prank(atlas);

        protocol.submitResult(
            1,
            "fuzz-result"
        );

        vm.prank(genesis);

        protocol.approveTask(1);

        vm.prank(atlas);

        protocol.withdrawPayment();

        vm.expectRevert(
            bytes("No payment available")
        );

        vm.prank(atlas);

        protocol.withdrawPayment();

        require(
            address(protocol).balance == 0,
            "Unexpected remaining funds"
        );
    }

    // FUZZ TEST 04
    // Reject unauthorized task approval

    function testFuzzUnauthorizedApproval(
        uint256 rawAmount
    ) public {

        uint256 amount = boundPayment(rawAmount);

        vm.prank(genesis);

        protocol.createTask{value: amount}(
            1,
            2,
            "Fuzz access control test",
            DURATION
        );

        vm.prank(atlas);

        protocol.submitResult(
            1,
            "fuzz-result"
        );

        vm.expectRevert(
            bytes("Not task requester")
        );

        vm.prank(atlas);

        protocol.approveTask(1);

        require(
            address(protocol).balance == amount,
            "Escrow changed after rejection"
        );
    }
}
