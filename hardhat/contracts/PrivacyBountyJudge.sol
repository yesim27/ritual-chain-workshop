// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PrecompileConsumer} from "./utils/PrecompileConsumer.sol";

contract PrivacyBountyJudge is PrecompileConsumer {
    uint256 public constant MAX_SUBMISSIONS = 10;
    uint256 public constant MAX_ANSWER_LENGTH = 2_000;
    uint256 public nextBountyId = 1;

    struct Commitment {
        bytes32 hash;
        bool revealed;
        string answer;
    }

    struct Bounty {
        address owner;
        string title;
        string rubric;
        uint256 reward;
        uint256 submissionDeadline;
        uint256 revealDeadline;
        bool judged;
        bool finalized;
        bytes aiReview;
        uint256 winnerIndex;
        address[] submitters;
    }

    struct ConvoHistory {
        string storageType;
        string path;
        string secretsName;
    }

    mapping(uint256 => Bounty) public bounties;
    mapping(uint256 => mapping(address => Commitment)) public commitments;

    event BountyCreated(uint256 indexed bountyId, address indexed owner, string title, uint256 reward);
    event CommitmentSubmitted(uint256 indexed bountyId, address indexed submitter);
    event AnswerRevealed(uint256 indexed bountyId, address indexed submitter);
    event AllAnswersJudged(uint256 indexed bountyId, bytes aiReview);
    event WinnerFinalized(uint256 indexed bountyId, uint256 winnerIndex, address winner, uint256 reward);

    modifier onlyOwner(uint256 bountyId) {
        require(msg.sender == bounties[bountyId].owner, "not bounty owner");
        _;
    }

    modifier bountyExists(uint256 bountyId) {
        require(bounties[bountyId].owner != address(0), "bounty not found");
        _;
    }

    /// @notice Create a new bounty with submission and reveal deadlines
    function createBounty(
        string calldata title,
        string calldata rubric,
        uint256 submissionDeadline,
        uint256 revealDeadline
    ) external payable returns (uint256 bountyId) {
        require(msg.value > 0, "reward required");
        require(submissionDeadline > block.timestamp, "submission deadline must be future");
        require(revealDeadline > submissionDeadline, "reveal deadline must be after submission");

        bountyId = nextBountyId++;
        Bounty storage bounty = bounties[bountyId];
        bounty.owner = msg.sender;
        bounty.title = title;
        bounty.rubric = rubric;
        bounty.reward = msg.value;
        bounty.submissionDeadline = submissionDeadline;
        bounty.revealDeadline = revealDeadline;
        bounty.winnerIndex = type(uint256).max;

        emit BountyCreated(bountyId, msg.sender, title, msg.value);
    }

    /// @notice Submit only a commitment hash during submission phase
    function submitCommitment(
        uint256 bountyId,
        bytes32 commitment
    ) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        require(block.timestamp < bounty.submissionDeadline, "submission phase closed");
        require(!bounty.judged && !bounty.finalized, "bounty closed");
        require(commitments[bountyId][msg.sender].hash == bytes32(0), "already submitted");
        require(bounty.submitters.length < MAX_SUBMISSIONS, "max submissions reached");

        commitments[bountyId][msg.sender] = Commitment({
            hash: commitment,
            revealed: false,
            answer: ""
        });
        bounty.submitters.push(msg.sender);

        emit CommitmentSubmitted(bountyId, msg.sender);
    }

    /// @notice Reveal answer after submission deadline
    function revealAnswer(
        uint256 bountyId,
        string calldata answer,
        bytes32 salt
    ) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        require(block.timestamp >= bounty.submissionDeadline, "reveal phase not started");
        require(block.timestamp < bounty.revealDeadline, "reveal phase closed");

        Commitment storage c = commitments[bountyId][msg.sender];
        require(c.hash != bytes32(0), "no commitment found");
        require(!c.revealed, "already revealed");
        require(bytes(answer).length <= MAX_ANSWER_LENGTH, "answer too long");

        bytes32 expected = keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId));
        require(expected == c.hash, "commitment mismatch");

        c.revealed = true;
        c.answer = answer;

        emit AnswerRevealed(bountyId, msg.sender);
    }

    /// @notice Judge all revealed answers with Ritual AI
    function judgeAll(
        uint256 bountyId,
        bytes calldata llmInput
    ) external bountyExists(bountyId) onlyOwner(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        require(block.timestamp >= bounty.revealDeadline, "reveal phase not over");
        require(!bounty.judged, "already judged");
        require(!bounty.finalized, "already finalized");

        uint256 revealedCount = 0;
        for (uint256 i = 0; i < bounty.submitters.length; i++) {
            if (commitments[bountyId][bounty.submitters[i]].revealed) {
                revealedCount++;
            }
        }
        require(revealedCount > 0, "no revealed submissions");

        bytes memory output = _executePrecompile(LLM_INFERENCE_PRECOMPILE, llmInput);

        (
            bool hasError,
            bytes memory completionData,
            ,
            string memory errorMessage,
        ) = abi.decode(output, (bool, bytes, bytes, string, ConvoHistory));

        require(!hasError, errorMessage);

        bounty.judged = true;
        bounty.aiReview = completionData;

        emit AllAnswersJudged(bountyId, completionData);
    }

    /// @notice Finalize winner and pay reward
    function finalizeWinner(
        uint256 bountyId,
        uint256 winnerIndex
    ) external bountyExists(bountyId) onlyOwner(bountyId) {
        Bounty storage bounty = bounties[bountyId];
        require(bounty.judged, "not judged yet");
        require(!bounty.finalized, "already finalized");
        require(winnerIndex < bounty.submitters.length, "invalid winner index");
        require(commitments[bountyId][bounty.submitters[winnerIndex]].revealed, "winner not revealed");

        bounty.finalized = true;
        bounty.winnerIndex = winnerIndex;

        address winner = bounty.submitters[winnerIndex];
        uint256 reward = bounty.reward;
        bounty.reward = 0;

        (bool ok, ) = payable(winner).call{value: reward}("");
        require(ok, "payment failed");

        emit WinnerFinalized(bountyId, winnerIndex, winner, reward);
    }

    /// @notice Get bounty details
    function getBounty(uint256 bountyId) external view bountyExists(bountyId)
        returns (
            address owner, string memory title, string memory rubric,
            uint256 reward, uint256 submissionDeadline, uint256 revealDeadline,
            bool judged, bool finalized, uint256 submissionCount, uint256 winnerIndex
        )
    {
        Bounty storage bounty = bounties[bountyId];
        return (
            bounty.owner, bounty.title, bounty.rubric,
            bounty.reward, bounty.submissionDeadline, bounty.revealDeadline,
            bounty.judged, bounty.finalized, bounty.submitters.length, bounty.winnerIndex
        );
    }

    /// @notice Get commitment info (hash only, answer hidden until revealed)
    function getCommitment(uint256 bountyId, address submitter) external view
        returns (bytes32 hash, bool revealed, string memory answer)
    {
        Commitment storage c = commitments[bountyId][submitter];
        // Only show answer if revealed
        return (c.hash, c.revealed, c.revealed ? c.answer : "");
    }
}