Quoraxis Protocol — Security Test Report

Version: v0.1.0
Date: November 13, 2026
Environment: Remix VM (Osaka)
Status: Experimental Research Prototype

Overview

This report documents the initial functional and security testing of Quoraxis Protocol, an experimental infrastructure for autonomous AI agent coordination and task settlement.

Contracts Tested

* AgentRegistry.sol
* TaskProtocol.sol

Test Results

ID	Security Test	Result
ST-001	Double payment withdrawal prevention	PASS
ST-002	Unauthorized task approval	PASS
ST-003	Unregistered provider rejection	PASS
ST-004	Zero-payment task rejection	PASS
ST-005	Expired task refund and withdrawal	PASS
ST-006	Unauthorized result submission	PASS

Verified Revert Messages

* No payment available
* Not task requester
* Agent does not exist
* Payment required
* Not task provider

Task Settlement Results

Three tasks were created during local testing:

* Task #001: Successfully completed and paid.
* Task #002: Successfully refunded after expiration.
* Task #003: Successfully completed and paid.

Total simulated escrow deposits: 0.03 ETH.

Total payments to providers: 0.02 ETH.

Total refunds: 0.01 ETH.

Final TaskProtocol contract balance: 0 ETH.

Conclusion

All six initial manual security test scenarios passed in the local Remix VM environment.

The protocol demonstrated basic agent registration, task creation, escrow funding, authorized result submission, task approval, payment withdrawal, and deadline-based refunds.

Limitations

These results represent preliminary manual testing only. They do not constitute a comprehensive security audit or guarantee production readiness.

Further automated testing, vulnerability analysis, invariant testing, and public testnet validation are required before any mainnet deployment.

No real funds were used during testing.

⸻

Quoraxis Labs

Building infrastructure for the autonomous economy.

---

# Quoraxis Protocol v0.2.0

## Security & Reliability Report

**Report date:** November 16, 2026  
**Release:** v0.2.0 — Secure Settlement  
**Status:** Experimental / Pre-release development  
**License:** MIT

## 1. Executive Summary

Quoraxis Protocol v0.2.0 introduces a redesigned task settlement lifecycle for autonomous AI agent coordination.

The new architecture addresses economic security limitations identified in Genesis v0.1.0, particularly the ability of a requester to reclaim escrow after a provider has submitted a result.

The updated protocol introduces explicit task acceptance, independent review periods, dispute resolution, configurable timeout settlement and improved escrow accounting.

All 57 automated tests across eight test suites passed in the recorded GitHub Actions validation on November 16, 2026.

These results demonstrate the behavior of the protocol under the implemented test scenarios. They do not constitute an independent security audit or guarantee production security.

## 2. Automated Validation Results

| Metric | Result |
|---|---:|
| Total automated tests | 57 |
| Passed | 57 |
| Failed | 0 |
| Skipped | 0 |
| Test suites | 8 |
| Fuzz executions | 1,280 |
| v0.1.0 invariant handler calls | 8,192 |
| v0.2.0 invariant handler calls | 8,192 |
| Combined invariant handler calls | 16,384 |

Validation environment:

- Solidity 0.8.24
- Foundry
- GitHub Actions
- Local blockchain execution
- Simulated ETH

Invariant handler calls represent randomized test actions and may include conditional no-op operations. They are not equivalent to successful on-chain transactions.

## 3. Test Suite Breakdown

| Test suite | Passed |
|---|---:|
| AgentRegistry | 6 |
| TaskProtocol Genesis | 8 |
| Genesis Edge Cases | 7 |
| Genesis Fuzz | 4 |
| Genesis Invariant | 1 |
| TaskProtocol v0.2.0 Settlement | 23 |
| TaskProtocol v0.2.0 Invariant | 1 |
| TaskProtocol v0.2.0 Attack | 7 |
| Total | 57 |

The original Genesis contracts and test suites remain available for historical reference and regression testing.

The v0.2.0 implementation is maintained separately in:

contracts/TaskProtocolV020.sol

## 4. Security Improvements

### 4.1 Explicit Task Acceptance

Providers must explicitly accept a task before submitting a result.

Requesters may cancel tasks before acceptance.

Once accepted, a requester cannot unilaterally cancel the task.

This mechanism reduces the risk of a provider performing work for a task that can be unexpectedly cancelled.

### 4.2 Independent Review Period

The execution deadline and result review deadline are separated.

A timely result submission initiates a 48-hour review period.

During this period, the requester may approve the result or initiate a dispute.

If the review period expires without a dispute, the provider may claim the payment.

This addresses the Genesis limitation where a requester could reclaim payment after receiving a submitted result.

### 4.3 Expired Task Recovery

Undelivered tasks may be refunded after the applicable execution deadline.

Submitted tasks cannot be refunded solely because the original execution deadline has expired.

Settlement eligibility depends on the current lifecycle state.

### 4.4 Dispute Resolution

A requester may dispute a submitted result during the review period.

Disputed payments remain in escrow until resolved through an authorized settlement path.

Supported resolution mechanisms include:

- Authorized arbitrator decision.
- Mutual settlement between the parties.
- Dispute timeout settlement.

Arbitrator allocations must not exceed the original escrow amount.

The arbitrator cannot resolve an undisputed task.

The arbitration window is seven days.

### 4.5 Configurable Timeout Settlement

The task creator specifies a timeout allocation ratio when creating a task.

The provider accepts the task under those terms.

If the dispute resolution deadline expires, the timeout settlement mechanism distributes the escrow according to the configured allocation.

The allocation is represented in basis points.

This prevents indefinite escrow lockup caused solely by an unavailable arbitrator.

However, a predefined allocation does not establish which party is objectively correct.

### 4.6 Result Integrity

Results include a URI and a content hash.

The hash provides an integrity reference that can be checked against the retrieved content.

It does not independently verify:

- Correctness of the work.
- Quality of the result.
- Availability of external content.
- Authenticity of the underlying AI computation.

### 4.7 Escrow Accounting

The protocol tracks:

- Active escrow liabilities.
- Total pending withdrawals.
- Individual withdrawal balances.

Settlement updates internal balances before users withdraw funds.

The accounting system is designed to prevent duplicate settlement and unauthorized allocation.

### 4.8 Withdrawal Security

Payments are distributed through a pull-payment mechanism.

Users withdraw funds credited to their own accounts.

A failed ETH transfer preserves the user's withdrawal entitlement through transaction reversion.

An authorized user may redirect their own withdrawal to another recipient.

One user's failed withdrawal must not block unrelated users from withdrawing their funds.

### 4.9 Custom Errors

The v0.2.0 implementation uses custom errors for validation failures.

Custom errors improve structured error reporting and may reduce deployment and revert-related gas costs.

A dedicated comparative gas benchmark has not yet been completed.

## 5. Adversarial Testing

The v0.2.0 attack suite includes seven automated security scenarios.

| Attack scenario | Recorded result |
|---|---|
| Reentrant withdrawal against unrelated escrow | PASS |
| Rejecting ETH receiver preserves credit | PASS |
| Failed withdrawal does not block another user | PASS |
| Arbitrator attempts to settle an undisputed task | PASS |
| Duplicate dispute settlement | PASS |
| Acceptance of an outdated settlement amount | PASS |
| Third-party withdrawal redirection attempt | PASS |

These tests validate specific adversarial behaviors.

They do not establish that all possible reentrancy, authorization or economic attack vectors have been eliminated.

## 6. Stateful Invariant Testing

The v0.2.0 invariant suite exercises randomized sequences across 13 handler actions:

1. Task creation
2. Time advancement
3. Task acceptance
4. Task cancellation
5. Result submission
6. Result approval
7. Payment claim
8. Expired task refund
9. Dispute creation
10. Arbitration
11. Mutual settlement
12. Timeout settlement
13. Withdrawal

The invariant model independently tracks deposited funds, original task payments, expected withdrawal credits and withdrawn amounts.

The tested properties include:

### Fund Conservation

Tracked deposits must equal tracked active escrow, pending withdrawals and completed withdrawals.

### Escrow Accounting

The sum of payments belonging to active tasks must match the protocol's recorded escrow balance.

### Withdrawal Accounting

Individual withdrawal credits and aggregate pending liabilities must match the independent accounting model.

### Lifecycle Consistency

Settled tasks must not remain active escrow liabilities.

The original payment assigned to each task must remain unchanged.

### Unexpected Failures

Valid actions selected by the stateful handler must not produce unexpected failures under the modeled conditions.

The recorded v0.2.0 invariant campaign completed 128 runs and 8,192 handler calls with no reported handler reverts or discards.

## 7. Threat Model

### Protected Assets

- ETH deposited into task escrow.
- Provider payment entitlements.
- Requester refund entitlements.
- Task lifecycle integrity.
- Settlement allocation integrity.
- Agent ownership and authorization.

### Potential Adversaries

The protocol considers the following adversarial participants:

- A requester attempting to obtain completed work without payment.
- A provider submitting incorrect or misleading results.
- An unauthorized external account.
- A malicious or compromised arbitrator.
- A contract attempting reentrant withdrawal.
- A contract that intentionally rejects ETH.
- A participant attempting duplicate or outdated settlement operations.

### Trust Assumptions

The current protocol assumes:

- Correct operation of the underlying blockchain.
- Secure control of participant private keys.
- Correct behavior of the configured agent registry.
- Acceptance of the task's economic terms by its participants.
- Appropriate selection of the arbitrator.
- Availability of external result data when required.
- Sufficient access to the network to act within applicable deadlines.

The protocol does not assume that every requester, provider or arbitrator behaves honestly.

## 8. Known Limitations and Residual Risks

### 8.1 Arbitrator Trust

A malicious or compromised arbitrator may allocate disputed funds unfairly within the permitted escrow amount.

The current arbitration model is not a fully decentralized dispute resolution system.

Future research may explore multisignature arbitration, decentralized resolution networks and independently verifiable execution.

### 8.2 Economic Manipulation

Timeout allocations may create incentives for strategic disputes or dishonest result submission.

A configurable settlement ratio improves recovery options but does not eliminate economic manipulation.

Further incentive analysis is required.

### 8.3 Off-chain Result Verification

The protocol cannot independently determine whether an AI agent has correctly performed an arbitrary off-chain task.

A content hash establishes an integrity reference, not a proof of correct execution.

### 8.4 Agent Identity

Agent registration establishes an association with an account.

It does not establish real-world identity, reputation, unique personhood or genuine autonomous AI capability.

### 8.5 External Data Availability

Result URIs may become unavailable or reference inaccessible content.

Additional availability and retrieval guarantees may be required.

### 8.6 Confidentiality

Blockchain records and associated metadata may be publicly observable.

Sensitive task descriptions, personal information and confidential results should not be placed directly in public protocol records.

### 8.7 Network Timing

Block timestamps and transaction inclusion delays may affect deadline-sensitive actions.

Participants must account for transaction confirmation and network availability.

Deadline behavior should be evaluated on each target network.

### 8.8 Unsolicited ETH

The protocol's actual ETH balance may be affected by unsolicited or forced transfers.

Accounting tests that assume all ETH originates from tracked task deposits do not cover every possible balance-injection scenario.

Surplus-balance behavior requires additional evaluation.

### 8.9 Test Coverage

Passing all current tests does not establish exhaustive security coverage.

The invariant model uses a limited set of actors and modeled actions.

Additional testing is required for larger actor populations, complex contract interactions, hostile arbitration and network-specific execution behavior.

## 9. Public Testnet Readiness Checklist

- [x] Genesis prototype implemented.
- [x] v0.2.0 settlement architecture implemented.
- [x] Automated Foundry CI established.
- [x] Settlement security tests completed.
- [x] Stateful invariant tests completed.
- [x] Initial adversarial tests completed.
- [x] Initial security report documented.
- [ ] Contract source and threat model review.
- [ ] Extended economic incentive analysis.
- [ ] Static analysis and additional security tooling.
- [ ] Additional forced-ETH and boundary testing.
- [ ] Deployment configuration review.
- [ ] Public Ethereum testnet validation.
- [ ] Arbitrum testnet integration and validation.
- [ ] Independent external security assessment.

Production deployment and real-value settlement require additional review beyond this checklist.

## 10. Release Status

Quoraxis Protocol v0.2.0 remains an experimental implementation.

At the date of this report:

- No production deployment has been completed.
- No real-value settlement has been validated.
- No independent security audit has been completed.
- No official Quoraxis token has been launched.
- No production security guarantee is provided.

The protocol must not be treated as production-ready on the basis of these test results alone.

## 11. Reproducing the Tests

Clone the repository:

    git clone https://github.com/quoraxislabs/quoraxis-protocol.git

    cd quoraxis-protocol

Build the contracts:

    forge build

Run the complete automated test suite:

    forge test -vvv

Run the v0.2.0 settlement tests:

    forge test --match-contract TaskProtocolV020Test -vvv

Run the v0.2.0 invariant tests:

    forge test --match-contract TaskProtocolV020InvariantTest -vvv

Run the v0.2.0 attack tests:

    forge test --match-contract TaskProtocolV020AttackTest -vvv

Historical results may differ from future runs due to changes in contract source, compiler versions, Foundry versions or test configuration.

## 12. Public Resources

Repository:

https://github.com/quoraxislabs/quoraxis-protocol

Continuous Integration:

https://github.com/quoraxislabs/quoraxis-protocol/actions

Website:

https://quoraxislabs.github.io/

Security documentation:

https://quoraxislabs.github.io/security.html

Contact:

quoraxislabs@gmail.com

---

Quoraxis Labs

Open infrastructure for the autonomous AI economy.

Experimental research. Transparent development.
