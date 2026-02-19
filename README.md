# ClarityBridge: Decentralized AI Chatbot Marketplace

## 1. Project Overview

**ClarityBridge** is a robust, decentralized marketplace built on the Stacks blockchain, designed to bridge the gap between users seeking intelligent automated responses and off-chain AI agents. By leveraging the security and transparency of Bitcoin-finalized smart contracts, ClarityBridge ensures that every interaction is trustless, every payment is verified, and every bot is held to a high standard of accountability.

In an era where AI services are often siloed and centralized, I have designed this contract to democratize access to AI by allowing a curated list of authorized bots to compete for requests. From standard queries to high-priority premium requests involving complex context, ClarityBridge manages the entire lifecycle of an AI interaction on-chain.

---

## 2. Key Features

* **Standard Chat Requests:** Users pay a flat base fee (**10 STX**) for standard question-and-answer interactions.
* **Premium Chat Requests:** A high-tier service (**50 STX**) that allows for extended context strings, priority levels (1-10), and urgent alerting for AI agents.
* **Bot Authorization:** A whitelist-based system ensures only verified, high-quality AI agents can fulfill requests, preventing on-chain spam.
* **Rating & Reputation:** A transparent feedback loop where requesters rate responses (1-5 stars) and provide comments, building a permanent record of bot performance.
* **Circuit Breaker:** Administrative "pause" functionality to secure the contract during maintenance or emergencies.

---

## 3. Detailed Function Reference

### A. Private Functions (Internal Logic)

I have encapsulated critical logic within private functions to ensure state consistency and prevent external manipulation.

* `is-paused`:
* **Logic:** Reads the `contract-paused` data variable.
* **Usage:** Used as a guardrail in all state-changing public functions to halt operations if the circuit breaker is active.


* `is-authorized-bot (bot-address principal)`:
* **Logic:** Performs a `map-get?` on the `authorized-bots` whitelist.
* **Usage:** Validates that only approved AI entities can submit responses to the `responses` map.


* `increment-nonce`:
* **Logic:** Retrieves the current `request-nonce`, increments it by 1, updates the variable, and returns the previous value.
* **Usage:** Guarantees unique, sequential IDs for every chat request.



---

### B. Public Functions (Write Operations)

#### Administrative

* `add-authorized-bot (bot principal)`: Adds a principal to the whitelist. Restricted to the `contract-owner`.
* `remove-authorized-bot (bot principal)`: Removes a principal from the whitelist. Restricted to the `contract-owner`.
* `set-paused (paused bool)`: Toggles the system status. Restricted to the `contract-owner`.
* `withdraw-fees (amount uint)`: Transfers micro-STX from the contract's balance to the owner.

#### Core Marketplace

* `request-standard-chat (prompt (string-utf8 256))`:
* **Fee:** 10,000,000 micro-STX.
* **Effect:** Creates a new request with a `pending` status and emits a `request-chat` print event.


* `request-premium-chat-with-context (prompt, context-data, priority-level, referral-code)`:
* **Fee:** 50,000,000 micro-STX.
* **Logic:** Validates priority (1-10), generates a `sha256` hash of the context for integrity, and triggers an `URGENT_PRIORITY_ALERT` if priority exceeds 8.


* `provide-response (request-id uint, response-text (string-utf8 256))`:
* **Requirement:** Caller must be an authorized bot.
* **Effect:** Links the response to the request and updates the status to `completed`.


* `rate-response (request-id uint, rating uint, comment (string-utf8 100))`:
* **Requirement:** Caller must be the original requester.
* **Validation:** Rating must be between `u1` and `u5`.



---

### C. Read-Only Functions (Getters)

I have provided these functions to allow front-end applications and off-chain indexers to query the state without gas costs.

* `get-request (id uint)`:
* **Returns:** An optional tuple containing the user principal, prompt, status, and premium flags.


* `get-response (id uint)`:
* **Returns:** An optional tuple containing the responder's principal, the text response, and the block height of the response.


* `get-stats`:
* **Returns:** A summary of total requests processed, total fees collected, and the current pause status.



---

## 4. Technical Architecture & Security

### The Checks-Effects-Interactions Pattern

I have followed the CEI pattern throughout the contract. For instance, in `request-standard-chat`, the contract first checks for a paused state, then executes the STX transfer (effect/interaction), and finally updates the internal maps (state change).

### Data Storage Tables

| Map Name | Key | Value Schema |
| --- | --- | --- |
| `requests` | `uint` | `{user, prompt, status, is-premium, created-at}` |
| `responses` | `uint` | `{responder, response-text, responded-at}` |
| `ratings` | `uint` | `{user, rating, comment}` |
| `authorized-bots` | `principal` | `bool` |

---

## 5. Contributing

I welcome contributions from the community to make ClarityBridge the gold standard for on-chain AI.

1. **Fork the Repository:** Create your own branch for features or bug fixes.
2. **Test Locally:** Use `clarinet test` to ensure all existing functionality remains intact.
3. **Submit a PR:** Provide a detailed description of your changes and why they improve the contract.

---

## 6. MIT License

```text
MIT License

Copyright (c) 2026 ClarityBridge Development Team

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

```

---

## 7. Disclaimer

This contract is provided "as-is." While I have taken great care in implementing security measures, users should interact with the marketplace at their own risk. AI responses are generated by independent bots and do not reflect the views of the contract developer.
