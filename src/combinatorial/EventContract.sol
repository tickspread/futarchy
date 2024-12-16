// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title EventContract
 * @notice Manages binary events with Gnosis CTF compatibility
 */
contract EventContract {
    uint256 private constant SCALE = 1e18;
    uint256 private constant OUTCOME_SLOTS = 2; // Always binary

    struct Event {
        uint256 eventId;
        address oracle;
        bytes32 questionId;
        uint256 outcome; // Between 0 and SCALE
        bool isSettled;
    }

    uint256 private nextEventId = 1;
    mapping(uint256 => Event) public events;

    event EventCreated(uint256 indexed eventId, address indexed oracle, bytes32 indexed questionId);

    event EventSettled(uint256 indexed eventId, address indexed oracle, bytes32 indexed questionId, uint256 outcome);

    // Gnosis-style event for compatibility
    event ConditionResolution(
        bytes32 indexed conditionId,
        address indexed oracle,
        bytes32 indexed questionId,
        uint256 outcomeSlotCount,
        uint256[] payoutNumerators
    );

    error EventDoesNotExist(uint256 eventId);
    error EventAlreadySettled(uint256 eventId);
    error NotDesignatedOracle(address sender, address oracle);
    error InvalidOutcome(uint256 outcome);
    error InvalidOracle(address oracle);
    error InvalidPayoutCount();
    error InvalidPayoutSum();
    error LengthMismatch();

    /**
     * @notice Creates a new event
     * @param oracle Address authorized to settle this event
     * @param questionId Identifier for the oracle's question
     * @return eventId The ID of the newly created event
     */
    function createEvent(address oracle, bytes32 questionId) public returns (uint256 eventId) {
        if (oracle == address(0)) revert InvalidOracle(oracle);

        eventId = nextEventId++;
        events[eventId] =
            Event({ eventId: eventId, oracle: oracle, questionId: questionId, outcome: 0, isSettled: false });

        emit EventCreated(eventId, oracle, questionId);
    }

    /**
     * @notice Gnosis-compatible condition preparation (always binary)
     * @param oracle Oracle address
     * @param questionId Question identifier
     * @param outcomeSlotCount Must be 2 for binary outcomes
     * @return eventId The ID of the newly created event
     */
    function prepareCondition(address oracle, bytes32 questionId, uint256 outcomeSlotCount)
        public
        returns (uint256 eventId)
    {
        if (outcomeSlotCount != OUTCOME_SLOTS) revert InvalidPayoutCount();
        return createEvent(oracle, questionId);
    }

    /**
     * @notice Settles an event with continuous outcome
     * @param eventId The ID of the event to settle
     * @param outcome The outcome value between 0 and SCALE (1e18)
     */
    function settleEvent(uint256 eventId, uint256 outcome) public {
        if (eventId >= nextEventId) revert EventDoesNotExist(eventId);
        if (outcome > SCALE) revert InvalidOutcome(outcome);

        Event storage evt = events[eventId];
        if (evt.isSettled) revert EventAlreadySettled(eventId);
        if (msg.sender != evt.oracle) revert NotDesignatedOracle(msg.sender, evt.oracle);

        evt.outcome = outcome;
        evt.isSettled = true;

        emit EventSettled(eventId, evt.oracle, evt.questionId, outcome);
    }

    /**
     * @notice Settles an event using Gnosis-style binary payouts
     * @param questionId The question ID (used to find the event)
     * @param payouts Binary payout array [a, b] where outcome = a/(a+b) * SCALE
     */
    function reportPayouts(bytes32 questionId, uint256[] calldata payouts) external {
        if (payouts.length != OUTCOME_SLOTS) revert InvalidPayoutCount();

        // Find the event with this oracle and questionId
        uint256 eventId = findEvent(msg.sender, questionId);
        Event storage evt = events[eventId];

        if (evt.isSettled) revert EventAlreadySettled(eventId);

        // Calculate normalized outcome
        uint256 sum = payouts[0] + payouts[1];
        if (sum == 0) revert InvalidPayoutSum();

        // Convert to our format, rounding down
        uint256 outcome = (payouts[0] * SCALE) / sum;
        evt.outcome = outcome;
        evt.isSettled = true;

        emit EventSettled(eventId, evt.oracle, evt.questionId, outcome);

        // Emit Gnosis-compatible event
        bytes32 conditionId = getConditionId(evt.oracle, evt.questionId, OUTCOME_SLOTS);
        emit ConditionResolution(conditionId, evt.oracle, evt.questionId, OUTCOME_SLOTS, payouts);
    }

    /**
     * @notice Batch settles multiple events
     * @param eventIds Array of event IDs to settle
     * @param outcomes Array of outcomes corresponding to the events
     */
    function batchSettleEvents(uint256[] calldata eventIds, uint256[] calldata outcomes) external {
        if (eventIds.length != outcomes.length) revert LengthMismatch();

        for (uint256 i = 0; i < eventIds.length; i++) {
            uint256 eventId = eventIds[i];
            if (events[eventId].oracle != msg.sender) {
                revert NotDesignatedOracle(msg.sender, events[eventId].oracle);
            }
        }

        for (uint256 i = 0; i < eventIds.length; i++) {
            settleEvent(eventIds[i], outcomes[i]);
        }
    }

    /**
     * @notice Find event by oracle and questionId
     * @param oracle Oracle address
     * @param questionId Question identifier
     * @return eventId The ID of the found event
     */
    function findEvent(address oracle, bytes32 questionId) public view returns (uint256) {
        for (uint256 i = 1; i < nextEventId; i++) {
            Event storage evt = events[i];
            if (evt.oracle == oracle && evt.questionId == questionId) {
                return i;
            }
        }
        revert EventDoesNotExist(0);
    }

    /**
     * @notice Retrieves the outcome of an event
     * @param eventId The ID of the event
     * @return isSettled Whether the event has been settled
     * @return outcome The outcome value between 0 and SCALE (valid if settled)
     * @return oracle The designated oracle address
     * @return questionId The question identifier
     */
    function getEventOutcome(uint256 eventId)
        public
        view
        returns (bool isSettled, uint256 outcome, address oracle, bytes32 questionId)
    {
        if (eventId >= nextEventId) revert EventDoesNotExist(eventId);

        Event storage evt = events[eventId];
        return (evt.isSettled, evt.outcome, evt.oracle, evt.questionId);
    }

    /**
     * @notice Returns condition ID in Gnosis format (must use 2 slots)
     * @param oracle Oracle address
     * @param questionId Question identifier
     * @param outcomeSlotCount Must be 2 for binary outcomes
     * @return Condition ID as used in Gnosis protocol
     */
    function getConditionId(address oracle, bytes32 questionId, uint256 outcomeSlotCount)
        public
        pure
        returns (bytes32)
    {
        if (outcomeSlotCount != OUTCOME_SLOTS) revert InvalidPayoutCount();
        return keccak256(abi.encodePacked(oracle, questionId, OUTCOME_SLOTS));
    }

    /**
     * @notice Helper function for condition ID (assumes binary outcome)
     * @param oracle Oracle address
     * @param questionId Question identifier
     * @return Condition ID for binary outcome
     */
    function getBinaryConditionId(address oracle, bytes32 questionId) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(oracle, questionId, OUTCOME_SLOTS));
    }

    /**
     * @notice Retrieves the settlement status and outcome of multiple events
     * @param eventIds Array of event IDs
     * @return statuses Array of booleans indicating settlement status
     * @return outcomes Array of outcomes (valid if settled)
     */
    function getEventsInfo(uint256[] calldata eventIds)
        external
        view
        returns (bool[] memory statuses, uint256[] memory outcomes)
    {
        uint256 length = eventIds.length;
        statuses = new bool[](length);
        outcomes = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            uint256 eventId = eventIds[i];
            if (eventId >= nextEventId) {
                statuses[i] = false;
                outcomes[i] = 0;
            } else {
                Event storage evt = events[eventId];
                statuses[i] = evt.isSettled;
                outcomes[i] = evt.outcome;
            }
        }
    }

    /**
     * @notice Checks if all given events are settled
     * @param eventIds Array of event IDs
     * @return allSettled True if all events are settled
     */
    function areEventsSettled(uint256[] calldata eventIds) external view returns (bool allSettled) {
        for (uint256 i = 0; i < eventIds.length; i++) {
            uint256 eventId = eventIds[i];
            if (eventId >= nextEventId || !events[eventId].isSettled) {
                return false;
            }
        }
        return true;
    }
}
