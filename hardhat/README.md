# Privacy-Preserving AI Bounty Judge

A commit-reveal bounty system on Ritual Chain where submissions stay hidden until judging is complete.

## Problem

In a standard bounty system, answers are public immediately after submission. Later participants can read earlier answers, copy ideas, and submit improved versions. This is unfair.

## Solution: Commit-Reveal Flow

Instead of submitting answers directly, participants submit a **commitment hash** during the submission phase. The real answer stays hidden until the reveal phase.

### Commitment Formula
```solidity
bytes32 commitment = keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId));
```

Including `msg.sender` and `bountyId` prevents copying another participant's commitment.

## Bounty Lifecycle

1. **Create** — Owner creates a bounty with title, rubric, submission deadline, and reveal deadline.
2. **Commit** — Participants submit only a hash before the submission deadline.
3. **Reveal** — After submission deadline, participants reveal their answer + salt.
4. **Judge** — After reveal deadline, owner calls `judgeAll()`. Ritual AI judges all revealed answers together.
5. **Finalize** — Owner calls `finalizeWinner()` with the winner index. Reward is paid automatically.

## Smart Contract Functions

| Function | Phase | Who |
|---|---|---|
| `createBounty()` | Setup | Owner |
| `submitCommitment()` | Submission | Participant |
| `revealAnswer()` | Reveal | Participant |
| `judgeAll()` | Judging | Owner |
| `finalizeWinner()` | Finalization | Owner |

## Architecture Comparison

### Commit-Reveal (Required Track)
- Answers hidden during submission phase ✅
- Answers become public before AI judging ⚠️
- Works on any EVM chain
- No external dependencies

### Ritual-Native TEE (Advanced Track)
- Answers stay encrypted until after AI judging ✅
- TEE executor decrypts submissions privately ✅
- AI judges without participants seeing each other's answers ✅
- Requires Ritual Chain infrastructure

## Reflection

In a bounty system, the **bounty details** (title, rubric, deadline) should be fully public so participants know what to build. **Submissions** should stay hidden during the submission phase to prevent copying. The **judging process** should be decided by AI for objectivity and speed, but the **final winner selection** should require human confirmation by the owner — AI can recommend, but a human should verify the result before funds are released. This hybrid approach balances automation with accountability.

## Test Plan

### Valid Cases
- Create bounty with correct deadlines → succeeds
- Submit commitment before deadline → succeeds
- Reveal answer with correct salt → succeeds
- Duplicate commitment rejected → reverts
- Wrong salt on reveal → reverts
- Reveal after reveal deadline → reverts
- judgeAll before reveal deadline → reverts
- finalizeWinner with unrevealed winner → reverts
- Winner receives correct reward → verified

## Contracts

| Contract | Description |
|---|---|
| `AIJudge.sol` | Original workshop contract (public submissions) |
| `PrivacyBountyJudge.sol` | Commit-reveal version (hidden submissions) |

## Network

Ritual Chain Testnet — Chain ID: 1979
