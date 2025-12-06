// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
  Chain of Custody — Track 2 (Open-Source Frameworks) Smart Contract
  ---------------------------------------------------------------
  Improved version:
  - Supports batch add (multiple item_ids per caseId).
  - Enforces that only the system creator can manage roles.
  - Uses isAdmin / isCreator / isOwnerRole mappings explicitly in modifiers
    so that access control cleanly matches the “creator vs owners” requirement.
*/

contract ChainOfCustody {
    // -------------------------
    // Roles
    // -------------------------
    mapping(address => bool) public isAdmin;
    mapping(address => bool) public isCreator;
    mapping(address => bool) public isOwnerRole; // "Owners" = actors allowed to check in/out

    // The original deployer who controls role management
    address public systemCreator;

    modifier onlySystemCreator() {
        require(msg.sender == systemCreator, "Only system creator");
        _;
    }

    modifier onlyAdmin() {
        require(isAdmin[msg.sender], "Not admin");
        _;
    }

    modifier onlyCreator() {
        require(isCreator[msg.sender], "Not creator");
        _;
    }

    modifier onlyOwnerOrAdmin() {
        require(
            isOwnerRole[msg.sender] || isAdmin[msg.sender],
            "Not owner/admin"
        );
        _;
    }

    // -------------------------
    // Evidence State & History
    // -------------------------
    enum State {
        NONE,
        CHECKEDIN,
        CHECKEDOUT,
        DISPOSED,
        DESTROYED,
        RELEASED
    }

    enum ActionType {
        ADD,
        CHECKOUT,
        CHECKIN,
        REMOVE
    }

    enum RemovalReason {
        NONE,
        DISPOSED,
        DESTROYED,
        RELEASED
    }

    struct HistoryEntry {
        ActionType action;
        State stateAfter;         // state of the item after the action
        uint256 timestamp;        // block timestamp when action occurred
        address actor;            // msg.sender who performed the action
        RemovalReason reason;     // populated for REMOVE (DISPOSED/DESTROYED/RELEASED)
        string metadata;          // optional info; e.g., RELEASED->owner name/info
    }

    struct Item {
        bytes16 caseId;           // case UUID (packed)
        uint32 itemId;            // 4-byte integer per spec
        address creator;          // who added it
        State state;              // current state
        bool exists;              // uniqueness guard
    }

    // itemId => Item
    mapping(uint32 => Item) public items;

    // itemId => full history
    mapping(uint32 => HistoryEntry[]) private _history;

    // caseId => list of itemIds
    mapping(bytes16 => uint32[]) private _caseToItems;

    // tracking all cases
    mapping(bytes16 => bool) private _caseSeen;
    bytes16[] private _allCases;

    // -------------------------
    // Events
    // -------------------------
    event RoleGranted(string role, address account);
    event RoleRevoked(string role, address account);

    event ItemAdded(bytes16 indexed caseId, uint32 indexed itemId, address indexed creator);
    event ItemCheckedOut(uint32 indexed itemId, address indexed by);
    event ItemCheckedIn(uint32 indexed itemId, address indexed by);
    event ItemRemoved(uint32 indexed itemId, RemovalReason reason, string info, address indexed by);

    // -------------------------
    // Constructor
    // -------------------------
    constructor() {
        systemCreator = msg.sender;
        isAdmin[msg.sender] = true;
        isCreator[msg.sender] = true;

        emit RoleGranted("ADMIN", msg.sender);
        emit RoleGranted("CREATOR", msg.sender);
    }

    // -------------------------
    // Role Management
    // -------------------------
    // Only the system creator may manage users/roles
    function grantAdmin(address account) external onlySystemCreator {
        isAdmin[account] = true;
        emit RoleGranted("ADMIN", account);
    }

    function revokeAdmin(address account) external onlySystemCreator {
        isAdmin[account] = false;
        emit RoleRevoked("ADMIN", account);
    }

    function grantCreator(address account) external onlySystemCreator {
        isCreator[account] = true;
        emit RoleGranted("CREATOR", account);
    }

    function revokeCreator(address account) external onlySystemCreator {
        isCreator[account] = false;
        emit RoleRevoked("CREATOR", account);
    }

    function grantOwner(address account) external onlySystemCreator {
        isOwnerRole[account] = true;
        emit RoleGranted("OWNER", account);
    }

    function revokeOwner(address account) external onlySystemCreator {
        isOwnerRole[account] = false;
        emit RoleRevoked("OWNER", account);
    }

    // -------------------------
    // Internal add helper
    // -------------------------
    function _addEvidenceInternal(bytes16 caseId, uint32 itemId) internal {
        require(!items[itemId].exists, "Duplicate itemId");

        items[itemId] = Item({
            caseId: caseId,
            itemId: itemId,
            creator: msg.sender,
            state: State.CHECKEDIN,
            exists: true
        });

        // track case
        if (!_caseSeen[caseId]) {
            _caseSeen[caseId] = true;
            _allCases.push(caseId);
        }
        _caseToItems[caseId].push(itemId);

        // history (ADD -> CHECKEDIN)
        _history[itemId].push(
            HistoryEntry({
                action: ActionType.ADD,
                stateAfter: State.CHECKEDIN,
                timestamp: block.timestamp,
                actor: msg.sender,
                reason: RemovalReason.NONE,
                metadata: ""
            })
        );

        emit ItemAdded(caseId, itemId, msg.sender);
    }

    // -------------------------
    // Core Functions (mapped to CLI-style commands)
    // -------------------------

    /// add: Add one item; state starts as CHECKEDIN
    /// Only creators may add evidence (matches "creator password" requirement).
    function addEvidence(bytes16 caseId, uint32 itemId) external onlyCreator {
        _addEvidenceInternal(caseId, itemId);
    }

    /// add (batch): Add multiple item_ids for the same caseId.
    /// This matches the spec's "more than one item_id may be given at a time".
    function addEvidenceBatch(bytes16 caseId, uint32[] calldata itemIds) external onlyCreator {
        require(itemIds.length > 0, "No itemIds");
        for (uint256 i = 0; i < itemIds.length; i++) {
            _addEvidenceInternal(caseId, itemIds[i]);
        }
    }

    /// checkout: Only from CHECKEDIN, only owners/admin
    function checkout(uint32 itemId) external onlyOwnerOrAdmin {
        Item storage it = items[itemId];
        require(it.exists, "Unknown item");
        require(it.state == State.CHECKEDIN, "Not CHECKEDIN");

        it.state = State.CHECKEDOUT;

        _history[itemId].push(
            HistoryEntry({
                action: ActionType.CHECKOUT,
                stateAfter: State.CHECKEDOUT,
                timestamp: block.timestamp,
                actor: msg.sender,
                reason: RemovalReason.NONE,
                metadata: ""
            })
        );

        emit ItemCheckedOut(itemId, msg.sender);
    }

    /// checkin: Only from CHECKEDOUT, only owners/admin
    function checkin(uint32 itemId) external onlyOwnerOrAdmin {
        Item storage it = items[itemId];
        require(it.exists, "Unknown item");
        require(it.state == State.CHECKEDOUT, "Not CHECKEDOUT");

        it.state = State.CHECKEDIN;

        _history[itemId].push(
            HistoryEntry({
                action: ActionType.CHECKIN,
                stateAfter: State.CHECKEDIN,
                timestamp: block.timestamp,
                actor: msg.sender,
                reason: RemovalReason.NONE,
                metadata: ""
            })
        );

        emit ItemCheckedIn(itemId, msg.sender);
    }

    /// remove: Only a creator may remove an item.
    /// - Item must currently be CHECKEDIN.
    /// - `reason` is optional *except* when it is RELEASED:
    ///     - If reason == RELEASED → ownerInfo is required.
    ///     - If reason == DISPOSED or DESTROYED → stored as given.
    ///     - If reason == NONE       → treated as a generic removal with no explicit reason.
    /// - After removal, no further actions on this item are possible because
    ///   its state is no longer CHECKEDIN or CHECKEDOUT.
    function removeItem(
        uint32 itemId,
        RemovalReason reason,
        string calldata ownerInfo
    ) external onlyCreator {
        Item storage it = items[itemId];

        require(it.exists, "Item does not exist");
        require(it.state == State.CHECKEDIN, "Item must be CHECKEDIN to remove");

        // Interpret the reason:
        if (reason == RemovalReason.RELEASED) {
            // RELEASED requires lawful owner info (-o owner in the spec)
            require(bytes(ownerInfo).length > 0, "Owner info required for RELEASED");
            it.state = State.RELEASED;
        } else if (reason == RemovalReason.DISPOSED) {
            it.state = State.DISPOSED;
        } else if (reason == RemovalReason.DESTROYED) {
            it.state = State.DESTROYED;
        } else {
            // reason == NONE (no -y given / "no reason specified"):
            // still move it to a terminal state so no further actions can occur.
            // You can choose DISPOSED as a generic "removed" outcome.
            it.state = State.DISPOSED;
        }

        _history[itemId].push(
            HistoryEntry({
                action: ActionType.REMOVE,
                stateAfter: it.state,
                timestamp: block.timestamp,
                actor: msg.sender,
                reason: reason,
                metadata: ownerInfo  // usually only non-empty for RELEASED
            })
        );

        emit ItemRemoved(itemId, reason, ownerInfo, msg.sender);
    }

    // -------------------------
    // Read / "show" Functions
    // -------------------------

    /// show cases
    /// Only owners or admins may view the list of cases 
    function listCases() external view onlyOwnerOrAdmin returns (bytes16[] memory) 
    {
        return _allCases;
    }

    /// show items -c <case_id>
    /// Only owners or admins may view items of a case 
    function listItems(bytes16 caseId) external view onlyOwnerOrAdmin returns (uint32[] memory) {
        return _caseToItems[caseId];
    }

    /// show history [-n num] [-r reverse]
    function getHistory(uint32 itemId, uint256 n, bool reverse)
        external
        view onlyOwnerOrAdmin
        returns (HistoryEntry[] memory out)
    {
        require(items[itemId].exists, "Unknown item");
        HistoryEntry[] storage h = _history[itemId];
        uint256 len = h.length;

        if (n == 0 || n > len) n = len;
        out = new HistoryEntry[](n);

        if (reverse) {
            // most recent first
            for (uint256 i = 0; i < n; i++) {
                out[i] = h[len - 1 - i];
            }
        } else {
            // oldest first
            uint256 start = len - n;
            for (uint256 i = 0; i < n; i++) {
                out[i] = h[start + i];
            }
        }
    }

    // -------------------------
    // Summary by Case
    // -------------------------

    /// summary -c <case_id>
    /// Returns:
    ///   uniqueItems, checkedIn, checkedOut, disposed, destroyed, released
    function summary(bytes16 caseId)
        external
        view
        returns (
            uint256 uniqueItems,
            uint256 checkedIn,
            uint256 checkedOut,
            uint256 disposed,
            uint256 destroyed,
            uint256 released
        )
    {
        uint32[] storage ids = _caseToItems[caseId];
        uniqueItems = ids.length;

        for (uint256 i = 0; i < ids.length; i++) {
            State s = items[ids[i]].state;
            if (s == State.CHECKEDIN) checkedIn++;
            else if (s == State.CHECKEDOUT) checkedOut++;
            else if (s == State.DISPOSED) disposed++;
            else if (s == State.DESTROYED) destroyed++;
            else if (s == State.RELEASED) released++;
        }
    }

    // -------------------------
    // Helpers
    // -------------------------

    function getItem(uint32 itemId) external view returns (Item memory) {
        require(items[itemId].exists, "Unknown item");
        return items[itemId];
    }

    function historyLength(uint32 itemId) external view returns (uint256) {
        require(items[itemId].exists, "Unknown item");
        return _history[itemId].length;
    }
}
