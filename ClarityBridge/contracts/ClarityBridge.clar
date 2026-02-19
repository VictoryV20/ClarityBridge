;; contract title: ai-chatbot-integration
;; contract description:
;; This contract serves as a decentralized marketplace for AI chatbot services.
;; It facilitates the interaction between users who request chat responses and
;; authorized off-chain AI agents (bots) that provide these responses.
;;
;; The contract includes the following features:
;; 1. Standard Chat Requests: Users pay a base fee to ask a question.
;; 2. Premium Chat Requests: Users pay a higher fee for priority handling and context.
;; 3. Response Management: Authorized bots listen to events and submit responses on-chain.
;; 4. Rating System: Users can rate the quality of the responses they receive.
;; 5. Administration: Context owner can manage authorized bots and pause the system.
;; 6. Financials: The contract collects fees which are held by the contract (or owner).
;;
;; Security considerations:
;; - Only authorized bots can submit responses to prevent spam or malicious answers.
;; - Only the original requester can rate a response.
;; - Administrative functions are restricted to the contract owner.
;; - Checks-Effects-Interactions pattern is used where possible.

;; =================================================================================
;; CONSTANTS
;; =================================================================================

;; The principal who deployed the contract and has admin privileges
(define-constant contract-owner tx-sender)

;; Error Codes
(define-constant err-not-authorized (err u100))    ;; Caller is not owner or authorized bot
(define-constant err-insufficient-balance (err u101)) ;; User cannot afford fee
(define-constant err-request-not-found (err u102))  ;; Request ID does not exist
(define-constant err-invalid-priority (err u103))   ;; Priority is out of bounds
(define-constant err-contract-paused (err u104))    ;; System is currently paused
(define-constant err-already-responded (err u105))  ;; Request already has a response
(define-constant err-not-requester (err u106))      ;; Caller is not the original requester
(define-constant err-invalid-rating (err u107))     ;; Rating is out of bounds (1-5)

;; System Configuration
(define-constant chat-price u10000000)          ;; 10 STX for standard request
(define-constant premium-chat-price u50000000)  ;; 50 STX for premium request
(define-constant min-rating u1)                 ;; Minimum rating value
(define-constant max-rating u5)                 ;; Maximum rating value

;; =================================================================================
;; DATA MAPS
;; =================================================================================

;; Stores the details of each chat request
(define-map requests
    uint ;; Request ID
    {
        user: principal,              ;; The user who made the request
        prompt: (string-utf8 256),    ;; The prompt text
        status: (string-ascii 20),    ;; Status: "pending", "completed", "premium-pending"
        is-premium: bool,             ;; Whether it was a premium request
        created-at: uint              ;; Block height when created
    }
)

;; Stores the response provided by the bot
(define-map responses
    uint ;; Request ID
    {
        responder: principal,         ;; The bot address that responded
        response-text: (string-utf8 256), ;; The response content
        responded-at: uint            ;; Block height when responded
    }
)

;; Stores user ratings for completed requests
(define-map ratings
    uint ;; Request ID
    {
        user: principal,              ;; User who gave the rating
        rating: uint,                 ;; Score 1-5
        comment: (string-utf8 100)    ;; Optional short comment
    }
)

;; Whitelist of authorized AI bot wallets
(define-map authorized-bots
    principal ;; Bot address
    bool      ;; Authorization status
)

;; =================================================================================
;; DATA VARIABLES
;; =================================================================================

;; Counter for generating unique request IDs
(define-data-var request-nonce uint u0)

;; Total fees collected by the contract in micro-STX
(define-data-var total-fees-collected uint u0)

;; Circuit breaker to pause operations in emergency
(define-data-var contract-paused bool false)

;; =================================================================================
;; PRIVATE FUNCTIONS
;; =================================================================================

;; @desc Checks if the contract is currently paused
;; @returns boolean true if paused, false otherwise
(define-private (is-paused)
    (var-get contract-paused)
)

;; @desc Verifies if a participant is an authorized bot
;; @param bot-address: The principal to check
;; @returns boolean true if authorized
(define-private (is-authorized-bot (bot-address principal))
    (default-to false (map-get? authorized-bots bot-address))
)

;; @desc Safely increments the request nonce
;; @returns The new request ID
(define-private (increment-nonce)
    (let ((current-nonce (var-get request-nonce)))
        (var-set request-nonce (+ current-nonce u1))
        current-nonce
    )
)

;; =================================================================================
;; PUBLIC FUNCTIONS - ADMINISTRATION
;; =================================================================================

;; @desc Add a new bot address to the authorized list
;; @param bot: The address to authorize
(define-public (add-authorized-bot (bot principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-not-authorized)
        (ok (map-set authorized-bots bot true))
    )
)

;; @desc Remove a bot address from the authorized list
;; @param bot: The address to de-authorize
(define-public (remove-authorized-bot (bot principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-not-authorized)
        (ok (map-delete authorized-bots bot))
    )
)

;; @desc Pause or unpause the contract
;; @param paused: New paused state
(define-public (set-paused (paused bool))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-not-authorized)
        (ok (var-set contract-paused paused))
    )
)

;; @desc Withdraw accumulated fees to the owner
;; @param amount: Amount to withdraw
(define-public (withdraw-fees (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-not-authorized)
        (try! (as-contract (stx-transfer? amount tx-sender contract-owner)))
        (ok amount)
    )
)

;; =================================================================================
;; PUBLIC FUNCTIONS - CORE FEATURES
;; =================================================================================

;; @desc Request a standard chat response from the AI
;; @param prompt: The text prompt for the chatbot
(define-public (request-standard-chat (prompt (string-utf8 256)))
    (let
        (
            (request-id (increment-nonce))
            (sender tx-sender)
        )
        ;; Pre-conditions
        (asserts! (not (is-paused)) err-contract-paused)
        
        ;; Payment
        (try! (stx-transfer? chat-price sender (as-contract tx-sender)))
        
        ;; State Update
        (map-set requests request-id {
            user: sender,
            prompt: prompt,
            status: "pending",
            is-premium: false,
            created-at: block-height
        })
        (var-set total-fees-collected (+ (var-get total-fees-collected) chat-price))
        
        ;; Event
        (print {event: "request-chat", id: request-id, user: sender, prompt: prompt, type: "standard"})
        (ok request-id)
    )
)

;; @desc Provide a response to a specific request ID (Authorized bots only)
;; @param request-id: The ID of the request being answered
;; @param response-text: The AI's response
(define-public (provide-response (request-id uint) (response-text (string-utf8 256)))
    (let
        (
            (request (unwrap! (map-get? requests request-id) err-request-not-found))
        )
        ;; Pre-conditions
        (asserts! (not (is-paused)) err-contract-paused)
        (asserts! (is-authorized-bot tx-sender) err-not-authorized)
        (asserts! (is-none (map-get? responses request-id)) err-already-responded)
        
        ;; State Update
        (map-set responses request-id {
            responder: tx-sender,
            response-text: response-text,
            responded-at: block-height
        })
        (map-set requests request-id (merge request { status: "completed" }))
        
        ;; Event
        (print {event: "response-provided", id: request-id, responder: tx-sender})
        (ok true)
    )
)

;; @desc Rate a response after it has been provided
;; @param request-id: The ID of the request to rate
;; @param rating: The rating score (1-5)
;; @param comment: a short comment
(define-public (rate-response (request-id uint) (rating uint) (comment (string-utf8 100)))
    (let
        (
            (request (unwrap! (map-get? requests request-id) err-request-not-found))
        )
        ;; Pre-conditions
        (asserts! (is-eq (get user request) tx-sender) err-not-requester)
        (asserts! (is-eq (get status request) "completed") err-request-not-found) ;; Must be completed
        (asserts! (and (>= rating min-rating) (<= rating max-rating)) err-invalid-rating)
        
        ;; State Update
        (map-set ratings request-id {
            user: tx-sender,
            rating: rating,
            comment: comment
        })
        
        ;; Event
        (print {event: "rating-submitted", id: request-id, rating: rating, user: tx-sender})
        (ok true)
    )
)

;; =================================================================================
;; SYSTEM GETTERS (READ-ONLY)
;; =================================================================================

(define-read-only (get-request (id uint))
    (map-get? requests id)
)

(define-read-only (get-response (id uint))
    (map-get? responses id)
)

(define-read-only (get-stats)
    {
        total-requests: (var-get request-nonce),
        total-fees: (var-get total-fees-collected),
        paused: (var-get contract-paused)
    }
)


