
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../contracts/AgentRegistry.sol";

interface Vm {
    function prank(address sender) external;
    function expectRevert() external;
}

contract AgentRegistryTest {

    Vm private constant vm = Vm(
        address(uint160(uint256(
            keccak256("hevm cheat code")
        )))
    );

    AgentRegistry private registry;

    address private genesis = address(0x1001);
    address private atlas = address(0x1002);

    function setUp() public {
        registry = new AgentRegistry();
    }

    // TEST 01
    // Verify successful agent registration

    function testRegisterAgent() public {

        vm.prank(genesis);

        registry.registerAgent(
            "Genesis",
            "https://quoraxislabs.github.io/"
        );

        AgentRegistry.Agent memory agent =
            registry.getAgent(1);

        require(agent.id == 1, "Invalid agent ID");

        require(
            agent.owner == genesis,
            "Invalid agent owner"
        );

        require(
            keccak256(bytes(agent.name)) ==
            keccak256(bytes("Genesis")),
            "Invalid agent name"
        );

        require(
            agent.active,
            "Agent should be active"
        );

        require(
            registry.agentCount() == 1,
            "Invalid agent count"
        );
    }

    // TEST 02
    // Verify sequential agent IDs

    function testMultipleAgents() public {

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

        require(
            registry.agentCount() == 2,
            "Invalid total agents"
        );

        AgentRegistry.Agent memory first =
            registry.getAgent(1);

        AgentRegistry.Agent memory second =
            registry.getAgent(2);

        require(
            first.owner == genesis,
            "Invalid first owner"
        );

        require(
            second.owner == atlas,
            "Invalid second owner"
        );

        require(
            first.id != second.id,
            "Duplicate agent IDs"
        );
    }

    // TEST 03
    // Verify owner can deactivate an agent

    function testDeactivateAgent() public {

        vm.prank(genesis);

        registry.registerAgent(
            "Genesis",
            "genesis-metadata"
        );

        vm.prank(genesis);

        registry.setAgentStatus(1, false);

        AgentRegistry.Agent memory agent =
            registry.getAgent(1);

        require(
            !agent.active,
            "Agent should be inactive"
        );
    }

    // TEST 04
    // Verify owner can reactivate an agent

    function testReactivateAgent() public {

        vm.prank(genesis);

        registry.registerAgent(
            "Genesis",
            "genesis-metadata"
        );

        vm.prank(genesis);
        registry.setAgentStatus(1, false);

        vm.prank(genesis);
        registry.setAgentStatus(1, true);

        AgentRegistry.Agent memory agent =
            registry.getAgent(1);

        require(
            agent.active,
            "Agent should be active"
        );
    }

    // TEST 05
    // Reject unauthorized status changes

    function testUnauthorizedStatusChange()
        public
    {

        vm.prank(genesis);

        registry.registerAgent(
            "Genesis",
            "genesis-metadata"
        );

        vm.expectRevert();

        vm.prank(atlas);

        registry.setAgentStatus(1, false);

        AgentRegistry.Agent memory agent =
            registry.getAgent(1);

        require(
            agent.active,
            "Unauthorized status change"
        );
    }

    // TEST 06
    // Reject nonexistent agents

    function testNonexistentAgent() public {

        vm.expectRevert();

        registry.getAgent(999);
    }
}
