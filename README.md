# Blockchain Chain of Custody – Track 2 (Open Source Framework)

**Course:** CSE 469 – Computer and Network Forensics  
**Track:** Track 2 – Open Source Blockchain Framework-based  
**Framework Used:** Ethereum smart contract (Solidity) + Remix IDE

---

## 1. Group Information

- **Group Name:** Group 13
- **Members:**
  - Kishan Venkatesan – 1233164870
  - Olivia Pratt – 1224918357
  - Zayn Shah – 1222620841
  - Ryan Clark - 1224137837
  - Faisal Alyousefi - 1227324880

---

## 2. Project Overview

This project implements a **digital chain of custody** system using an **Ethereum smart contract**.  
It corresponds to the Track-2 specification:

- Provides commands equivalent to:
  - `add` / `add` with multiple item IDs
  - `checkout`
  - `checkin`
  - `remove`
  - `show cases`
  - `show items`
  - `show history`
  - `summary`
- Enforces:
  - Evidence item uniqueness
  - State transitions (`CHECKEDIN`, `CHECKEDOUT`, `DISPOSED`, `DESTROYED`, `RELEASED`)
  - Access control for creators vs owners/admins
- Uses a **real blockchain framework** (Ethereum) instead of a custom file-based blockchain.

We model **passwords** from the original spec as **Ethereum addresses with roles**:

- `systemCreator` – deploys the contract and is the only one allowed to **grant/revoke roles**.
- `CREATOR` role – may add evidence and remove evidence.
- `OWNER` role – may check evidence in/out and view case/item details.
- `ADMIN` role – may act like an owner for some operations.

---

## 3. Smart Contract Summary

Source file: `contracts/ChainOfCustody.sol`

Key concepts:

- **Item struct**
  - `caseId: bytes16` – UUID of the case (stored without dashes).
  - `itemId: uint32` – unique evidence item identifier.
  - `creator: address` – address that added the item.
  - `state: State` – current state (CHECKEDIN, CHECKEDOUT, DISPOSED, DESTROYED, RELEASED).
  - `exists: bool` – ensures item IDs cannot be reused.

- **HistoryEntry struct**
  - Stores a chronological list of actions for each item:
    - `action` (ADD, CHECKOUT, CHECKIN, REMOVE)
    - `stateAfter`
    - `timestamp`
    - `actor`
    - `reason` (for REMOVE)
    - `metadata` (e.g., owner info for RELEASED)

- **States**
  - `CHECKEDIN`, `CHECKEDOUT`, `DISPOSED`, `DESTROYED`, `RELEASED`.

- **Removal reasons**
  - `DISPOSED`, `DESTROYED`, `RELEASED`, or `NONE` (no explicit reason).

---

## 4. Command Mapping (Spec → Solidity Functions)

Original CLI concept → Contract function:

- **`add -c case_id -i item_id`**
  - `addEvidence(bytes16 caseId, uint32 itemId)`
  - New item starts in `CHECKEDIN`.
  - Only callers with **CREATOR** role.

- **`add -c case_id -i item_id1 item_id2 ...`** (multiple IDs)
  - `addEvidenceBatch(bytes16 caseId, uint32[] itemIds)`
  - Adds multiple items for the same case in one call.
  - Only **CREATOR** role.

- **`checkout -i item_id`**
  - `checkout(uint32 itemId)`
  - Allowed only if current state is `CHECKEDIN`.
  - Only **OWNER** or **ADMIN**.

- **`checkin -i item_id`**
  - `checkin(uint32 itemId)`
  - Allowed only if current state is `CHECKEDOUT`.
  - Only **OWNER** or **ADMIN**.

- **`remove -i item_id [-y reason] [-o owner]`**
  - `removeItem(uint32 itemId, RemovalReason reason, string ownerInfo)`
  - Allowed only when state is `CHECKEDIN`.
  - `reason`:
    - `NONE` – generic remove, no explicit reason.
    - `DISPOSED` – disposed.
    - `DESTROYED` – destroyed.
    - `RELEASED` – released to lawful owner (requires `ownerInfo` to be non-empty).
  - After `removeItem`, no further `add/checkout/checkin/remove` is possible for that `itemId`.
  - Only **CREATOR** role.

- **`show cases`**
  - `listCases()`
  - Returns all case IDs that exist.
  - Only **OWNER** or **ADMIN**.

- **`show items -c case_id`**
  - `listItems(bytes16 caseId)`
  - Returns all item IDs for that case.
  - Only **OWNER** or **ADMIN**.

- **`show history -i item_id [-n num] [-r]`**
  - `getHistory(uint32 itemId, uint256 n, bool reverse)`
  - `n == 0` → full history.
  - `reverse == false` → oldest-first.
  - `reverse == true` → newest-first.
  - (Currently readable by anyone; can be restricted in the contract if required.)

- **`summary -c case_id`**
  - `summary(bytes16 caseId)`
  - Returns:
    - number of unique items for the case
    - counts of items that are currently:
      - `CHECKEDIN`
      - `CHECKEDOUT`
      - `DISPOSED`
      - `DESTROYED`
      - `RELEASED`.

> Note: `init` and `verify` commands from the original file-based spec are not needed in Ethereum:  
> - **Genesis block** already exists on the chain.  
> - **Block verification & hashing** are enforced by Ethereum itself.

---

## 5. Prerequisites

You **do not** need to install Hardhat/Fabric/Docker to run this project.

You only need:

- A modern web browser (Chrome, Firefox, Edge, etc.).
- Internet connection.
- Access to **Remix IDE**:  
  https://remix.ethereum.org

---

## 6. How to Set Up Environment and Run (Step-by-Step in Remix)

We use **Remix VM (London)** which provides 10 fake accounts with ETH and an in-memory blockchain.

### Environment Set-Up

#### 6.1 Load the contract into Remix

1. Open **https://remix.ethereum.org**
2. In the **File Explorer** (left side):
   - Click **“+”** → create new file: `ChainOfCustody.sol`
   - Copy the contract code from `contracts/ChainOfCustody.sol` in this repo and paste it.
3. Go to the **Solidity Compiler** tab:
   - Set compiler version to `0.8.20` (or the pragma used in the contract).
   - In Advanced Configurations, set EVM Version to london
   - Click **Compile ChainOfCustody.sol**.

#### 6.2 Deploy the contract

1. Go to the **Deploy & Run Transactions** tab.
2. Set:
   - **Environment**: `Remix VM (London)`
   - **Account**: leave default (this will be the **systemCreator** / admin).
   - **Contract**: `ChainOfCustody`.
3. Click **Deploy**.
4. A new entry appears under **Deployed Contracts**. Expand it to see all functions.

#### 6.3 Assign roles (system creator → Creator + Owner)

We simulate three roles with three Remix accounts:

- Account #0 (default) → **systemCreator** (admin and creator by default).
- Account #1 → **CREATOR** role (can add/remove).
- Account #2 → **OWNER** role (can check in/out & view).

##### 6.3.1 Get addresses

1. In the **Account** dropdown at the top of Deploy & Run:
   - Note/copy **Account #1** address (second entry).
   - Note/copy **Account #2** address (third entry).

##### 6.3.2 Grant Creator and Owner roles

1. Make sure **Account #0** (first account) is selected (systemCreator).
2. In the deployed contract interface:
   - For `grantCreator(address account)`:
     - Paste **Account #1** address.
     - Click **transact**.
   - For `grantOwner(address account)`:
     - Paste **Account #2** address.
     - Click **transact**.

(You can call `isCreator(account1)` and `isOwnerRole(account2)` to verify they’re `true`.)

---
### Running the Project

#### 6.4 Example: add, checkout, checkin, remove, summary, history
We’ll use:

- **Case ID (UUID)**: `c84e339e-5c0f-4f4d-84c5-bb79a3c1d2a2`
- **Case ID as `bytes16`**: `0xc84e339e5c0f4f4d84c5bb79a3c1d2a2`
- **Item IDs**: `1004820154`, `1004820155`  

#### 6.4.1 Add multiple items (Creator)

1. Switch **Account** to **Account #1** (the creator).
2. In the deployed contract:
   - For `addEvidenceBatch(bytes16 caseId, uint32[] itemIds)`:
     - `caseId` =  
       `0xc84e339e5c0f4f4d84c5bb79a3c1d2a2`
     - `itemIds` = `[1004820154, 1004820155]`
   - Click **transact**.

Now both items are created and in `CHECKEDIN` state.

(You could also use `addEvidence(caseId, singleItemId)` for one-by-one adds.)

#### 6.4.2 Checkout & checkin (Owner)

1. Switch **Account** to **Account #2** (owner).
2. In the deployed contract:
   - Call `checkout(1004820154)` → item 1004820154 moves to `CHECKEDOUT`.
   - Call `checkin(1004820154)` → item 1004820154 moves back to `CHECKEDIN`.

#### 6.4.3 Remove one item (Creator)

1. Switch **Account** back to **Account #1** (creator).
2. To mark as RELEASED (with lawful owner info):
   - Call:
     - `removeItem(1004820154, RemovalReason.RELEASED, "Released to lawful owner")`
   - In Remix, you’ll choose the enum index for `RemovalReason.RELEASED` and pass the string:
     - `itemId` = `1004820154`
     - `reason` = `3` (if enum order is NONE=0, DISPOSED=1, DESTROYED=2, RELEASED=3)
     - `ownerInfo` = `"Released to lawful owner"`

Now item 1004820154 is in terminal state `RELEASED` and cannot be checked out/in or re-added.

#### 6.4.4 Show cases and items (Owner/Admin only)

1. Switch to **Account #2** (owner) or keep Account #0 (admin).
2. Call:
   - `listCases()` → you should see `[0xc84e339e5c0f4f4d84c5bb79a3c1d2a2]`
   - `listItems(0xc84e339e5c0f4f4d84c5bb79a3c1d2a2)` → ` [1004820154, 1004820155]`

#### 6.4.5 Summary (per case)

Call:

- `summary(0xc84e339e5c0f4f4d84c5bb79a3c1d2a2)`

You’ll get:

- `uniqueItems` = 2
- `checkedIn` = 1 (item 1004820155)
- `checkedOut` = 0
- `disposed`, `destroyed` depending on future actions
- `released` = 1 (item 1004820154)

#### 6.4.6 History (per item)

Call:

- `getHistory(1004820154, 0, false)` → full history, oldest first.
- `getHistory(1004820154, 0, true)` → full history, newest first.

You’ll see the sequence:
- ADD
- CHECKOUT
- CHECKIN
- REMOVE (RELEASED)

---

## 7. How This Satisfies Track-2 Requirements

Per the assignment:

- Uses an **open-source blockchain framework** (Ethereum).
- Implements:
  - add, checkout, checkin, remove.
  - show cases, show items, show history.
  - summary by case.
- Enforces:
  - Unique item IDs; no re-adding after removal.
  - Correct state transitions (`CHECKEDIN` → `CHECKEDOUT` → `CHECKEDIN` → `REMOVED`).
  - Role-based authorization matching the “creator vs owners” requirement.
- Explains in the report:
  - Why `init` and `verify` are not needed on Ethereum.
  - Why we use Ethereum accounts and roles instead of text passwords.
  - How transactions and blocks store the chain-of-custody history.

---

## 8. Demo Video

**Demo Video Link:** [\<Demo Link\>](https://youtu.be/mXbfnTzFkh8)

---

## 9. Generative AI Acknowledgment

> **Generative AI Acknowledgment:**  
> Portions of the code and documentation in this project were generated with assistance from ChatGPT, an AI tool developed by OpenAI.  
> Reference: OpenAI. (2024). *ChatGPT* [Large language model]. openai.com/chatgpt


