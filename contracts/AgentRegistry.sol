// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Quoraxis Agent Registry
 * @notice Experimental registry for autonomous AI agents.
 * @dev Version 0.1 - Research prototype.
 */

contract AgentRegistry {

    struct Agent {
        uint256 id;
        address owner;
        string name;
        string metadataURI;
        bool active;
        uint256 createdAt;
    }

    uint256 public agentCount;

    mapping(uint256 => Agent) private agents;

    event AgentRegistered(
        uint256 indexed agentId,
        address indexed owner,
        string name
    );

    event AgentUpdated(
        uint256 indexed agentId
    );

    event AgentStatusChanged(
        uint256 indexed agentId,
        bool active
    );

    modifier onlyAgentOwner(uint256 agentId) {
        require(
            agents[agentId].owner == msg.sender,
            "Not agent owner"
        );
        _;
    }

    function registerAgent(
        string calldata name,
        string calldata metadataURI
    ) external returns (uint256) {

        require(
            bytes(name).length > 0,
            "Name required"
        );

        agentCount++;

        uint256 agentId = agentCount;

        agents[agentId] = Agent({
            id: agentId,
            owner: msg.sender,
            name: name,
            metadataURI: metadataURI,
            active: true,
            createdAt: block.timestamp
        });

        emit AgentRegistered(
            agentId,
            msg.sender,
            name
        );

        return agentId;
    }

    function getAgent(
        uint256 agentId
    ) external view returns (Agent memory) {

        require(
            agentId > 0 && agentId <= agentCount,
            "Agent does not exist"
        );

        return agents[agentId];
    }

    function updateAgent(
        uint256 agentId,
        string calldata name,
        string calldata metadataURI
    ) external onlyAgentOwner(agentId) {

        require(
            bytes(name).length > 0,
            "Name required"
        );

        agents[agentId].name = name;
        agents[agentId].metadataURI = metadataURI;

        emit AgentUpdated(agentId);
    }

    function setAgentStatus(
        uint256 agentId,
        bool active
    ) external onlyAgentOwner(agentId) {

        agents[agentId].active = active;

        emit AgentStatusChanged(
            agentId,
            active
        );
    }

    function version()
        external
        pure
        returns (string memory)
    {
        return "0.1.0";
    }
}
