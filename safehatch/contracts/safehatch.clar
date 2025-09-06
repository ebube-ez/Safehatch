;; SafeHatch - Multi-Party Escrow System
;; Secure transactions between buyer, seller, and arbiter with comprehensive dispute resolution

;; Error constants
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-INVALID-STATE (err u400))
(define-constant ERR-INVALID-PARAMS (err u422))
(define-constant ERR-ALREADY-EXISTS (err u409))
(define-constant ERR-INSUFFICIENT-FUNDS (err u402))
(define-constant ERR-EXPIRED (err u408))
(define-constant ERR-CONTRACT-PAUSED (err u503))
(define-constant ERR-TRANSFER-FAILED (err u500))
(define-constant ERR-INVALID-PERCENTAGE (err u423))
(define-constant ERR-ESCROW-NOT-ACTIVE (err u424))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-FEE-RATE u1000)    ;; 10%
(define-constant MAX-DURATION u52560)   ;; ~1 year in blocks
(define-constant MIN-AMOUNT u1000)      ;; Minimum escrow amount (0.001 STX)
(define-constant MAX-PROTOCOL-FEE u500) ;; 5%
(define-constant MIN-DISPUTE-REASON-LENGTH u10)
(define-constant MAX-DISPUTE-REASON-LENGTH u256)
(define-constant MAX-ARBITER-NAME-LENGTH u64)
(define-constant PERCENTAGE-PRECISION u10000) ;; 100.00%

;; Data variables
(define-data-var next-escrow-id uint u1)
(define-data-var protocol-fee uint u50)  ;; 0.5%
(define-data-var fee-recipient principal CONTRACT-OWNER)
(define-data-var contract-paused bool false)
(define-data-var total-escrows-created uint u0)
(define-data-var total-volume uint u0)
(define-data-var emergency-mode bool false)

;; Main escrow data structure
(define-map escrows
  { id: uint }
  {
    creator: principal,
    buyer: principal,
    seller: principal,
    arbiter: principal,
    amount: uint,
    status: (string-ascii 16),
    created-at: uint,
    expires-at: (optional uint),
    buyer-confirmed: bool,
    seller-confirmed: bool,
    funded-amount: uint,
    dispute-reason: (optional (string-utf8 256)),
    last-activity: uint,
    metadata: (optional (string-utf8 128))
  }
)

;; Deposits tracking for audit trail
(define-map deposits
  { escrow-id: uint }
  { 
    depositor: principal, 
    amount: uint, 
    timestamp: uint,
    block-height: uint
  }
)

;; Arbiters registry with reputation system
(define-map arbiters
  { arbiter: principal }
  {
    name: (string-utf8 64),
    fee-rate: uint,
    disputes-resolved: uint,
    disputes-won-buyer: uint,
    disputes-won-seller: uint,
    active: bool,
    registered-at: uint,
    last-activity: uint,
    reputation-score: uint
  }
)

;; Escrow participants for quick lookups
(define-map escrow-participants
  { escrow-id: uint, participant: principal }
  { role: (string-ascii 16), joined-at: uint }
)

;; Transaction history for transparency
(define-map transaction-history
  { escrow-id: uint, sequence: uint }
  {
    action: (string-ascii 32),
    actor: principal,
    timestamp: uint,
    block-height: uint,
    details: (optional (string-utf8 256))  ;; increased from 128 to 256 to match dispute reason length
  }
)

;; Transaction sequence tracking
(define-map transaction-sequences
  { escrow-id: uint }
  { next-sequence: uint }
)

;; Helper functions for validation and calculations
(define-private (is-valid-amount (amount uint))
  (and (> amount u0) (>= amount MIN-AMOUNT))
)

(define-private (is-valid-principal (user principal))
  (not (is-eq user (as-contract tx-sender)))
)

(define-private (is-participant (user principal) (buyer principal) (seller principal))
  (or (is-eq user buyer) (is-eq user seller))
)

(define-private (is-contract-paused)
  (var-get contract-paused)
)

(define-private (is-emergency-mode)
  (var-get emergency-mode)
)

(define-private (calculate-protocol-fee (amount uint))
  (/ (* amount (var-get protocol-fee)) PERCENTAGE-PRECISION)
)

(define-private (calculate-arbiter-fee (amount uint) (fee-rate uint))
  (/ (* amount fee-rate) PERCENTAGE-PRECISION)
)

(define-private (is-escrow-expired (escrow-data (tuple (creator principal) (buyer principal) (seller principal) (arbiter principal) (amount uint) (status (string-ascii 16)) (created-at uint) (expires-at (optional uint)) (buyer-confirmed bool) (seller-confirmed bool) (funded-amount uint) (dispute-reason (optional (string-utf8 256))) (last-activity uint) (metadata (optional (string-utf8 128))))))
  (match (get expires-at escrow-data)
    expiry (> block-height expiry)
    false
  )
)

(define-private (validate-dispute-reason (reason (string-utf8 256)))
  (let ((reason-length (len reason)))
    (and 
      (>= reason-length MIN-DISPUTE-REASON-LENGTH)
      (<= reason-length MAX-DISPUTE-REASON-LENGTH)
    )
  )
)

;; Fixed add-transaction-record function to properly track sequence numbers
(define-private (add-transaction-record (escrow-id uint) (action (string-ascii 32)) (details (optional (string-utf8 256))))  ;; updated parameter type from 128 to 256
  (let ((current-seq-data (default-to { next-sequence: u1 } (map-get? transaction-sequences { escrow-id: escrow-id })))
        (sequence (get next-sequence current-seq-data)))
    
    ;; Update sequence counter
    (map-set transaction-sequences
      { escrow-id: escrow-id }
      { next-sequence: (+ sequence u1) }
    )
    
    ;; Add transaction record
    (map-set transaction-history
      { escrow-id: escrow-id, sequence: sequence }
      {
        action: action,
        actor: tx-sender,
        timestamp: block-height,
        block-height: block-height,
        details: details
      }
    )
  )
)

;; Create escrow with enhanced validation
(define-public (create-escrow
  (buyer principal)
  (seller principal)
  (arbiter principal)
  (amount uint)
  (duration-blocks (optional uint))
  (metadata (optional (string-utf8 128))))
  
  (let ((escrow-id (var-get next-escrow-id)))
    
    ;; Basic validations
    (asserts! (not (is-contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (not (is-emergency-mode)) ERR-CONTRACT-PAUSED)
    (asserts! (is-valid-amount amount) ERR-INVALID-PARAMS)
    (asserts! (is-valid-principal buyer) ERR-INVALID-PARAMS)
    (asserts! (is-valid-principal seller) ERR-INVALID-PARAMS)
    (asserts! (is-valid-principal arbiter) ERR-INVALID-PARAMS)
    (asserts! (not (is-eq buyer seller)) ERR-INVALID-PARAMS)
    (asserts! (not (is-eq buyer arbiter)) ERR-INVALID-PARAMS)
    (asserts! (not (is-eq seller arbiter)) ERR-INVALID-PARAMS)
    
    ;; Validate arbiter exists and is active
    (let ((arbiter-data (unwrap! (map-get? arbiters { arbiter: arbiter }) ERR-NOT-FOUND)))
      (asserts! (get active arbiter-data) ERR-UNAUTHORIZED)
      
      ;; Validate duration if provided
      (match duration-blocks
        blocks (asserts! (and (> blocks u0) (<= blocks MAX-DURATION)) ERR-INVALID-PARAMS)
        true
      )
      
      ;; Calculate expiration
      (let ((expiry (match duration-blocks
                      blocks (some (+ block-height blocks))
                      none)))
        
        ;; Create escrow record
        (map-set escrows
          { id: escrow-id }
          {
            creator: tx-sender,
            buyer: buyer,
            seller: seller,
            arbiter: arbiter,
            amount: amount,
            status: "created",
            created-at: block-height,
            expires-at: expiry,
            buyer-confirmed: false,
            seller-confirmed: false,
            funded-amount: u0,
            dispute-reason: none,
            last-activity: block-height,
            metadata: metadata
          }
        )
        
        ;; Add participants
        (map-set escrow-participants { escrow-id: escrow-id, participant: buyer } { role: "buyer", joined-at: block-height })
        (map-set escrow-participants { escrow-id: escrow-id, participant: seller } { role: "seller", joined-at: block-height })
        (map-set escrow-participants { escrow-id: escrow-id, participant: arbiter } { role: "arbiter", joined-at: block-height })
        
        ;; Add transaction record
        (add-transaction-record escrow-id "created" metadata)
        
        ;; Update counters
        (var-set next-escrow-id (+ escrow-id u1))
        (var-set total-escrows-created (+ (var-get total-escrows-created) u1))
        
        (ok escrow-id)
      )
    )
  )
)

;; Register as arbiter with enhanced profile
(define-public (register-arbiter (name (string-utf8 64)) (fee-rate uint))
  (begin
    (asserts! (not (is-contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (<= fee-rate MAX-FEE-RATE) ERR-INVALID-PARAMS)
    (asserts! (> (len name) u0) ERR-INVALID-PARAMS)
    (asserts! (<= (len name) MAX-ARBITER-NAME-LENGTH) ERR-INVALID-PARAMS)
    (asserts! (is-none (map-get? arbiters { arbiter: tx-sender })) ERR-ALREADY-EXISTS)
    (asserts! (is-valid-principal tx-sender) ERR-INVALID-PARAMS)
    
    (map-set arbiters
      { arbiter: tx-sender }
      {
        name: name,
        fee-rate: fee-rate,
        disputes-resolved: u0,
        disputes-won-buyer: u0,
        disputes-won-seller: u0,
        active: true,
        registered-at: block-height,
        last-activity: block-height,
        reputation-score: u5000  ;; Start with neutral reputation (50%)
      }
    )
    
    (ok true)
  )
)

;; Update arbiter profile
(define-public (update-arbiter-profile (name (optional (string-utf8 64))) (fee-rate (optional uint)))
  (let ((arbiter-data (unwrap! (map-get? arbiters { arbiter: tx-sender }) ERR-NOT-FOUND)))
    
    ;; Validate new fee rate if provided
    (match fee-rate
      new-rate (asserts! (<= new-rate MAX-FEE-RATE) ERR-INVALID-PARAMS)
      true
    )
    
    ;; Validate new name if provided
    (match name
      new-name (begin
        (asserts! (> (len new-name) u0) ERR-INVALID-PARAMS)
        (asserts! (<= (len new-name) MAX-ARBITER-NAME-LENGTH) ERR-INVALID-PARAMS)
      )
      true
    )
    
    (map-set arbiters
      { arbiter: tx-sender }
      (merge arbiter-data {
        name: (default-to (get name arbiter-data) name),
        fee-rate: (default-to (get fee-rate arbiter-data) fee-rate),
        last-activity: block-height
      })
    )
    
    (ok true)
  )
)

;; Toggle arbiter status
(define-public (toggle-arbiter-status)
  (let ((arbiter-data (unwrap! (map-get? arbiters { arbiter: tx-sender }) ERR-NOT-FOUND)))
    (map-set arbiters
      { arbiter: tx-sender }
      (merge arbiter-data { 
        active: (not (get active arbiter-data)),
        last-activity: block-height
      })
    )
    (ok true)
  )
)

;; Fund escrow with STX
(define-public (fund-escrow (escrow-id uint))
  (let ((escrow-data (unwrap! (map-get? escrows { id: escrow-id }) ERR-NOT-FOUND)))
    
    ;; Validations
    (asserts! (not (is-contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (is-eq (get status escrow-data) "created") ERR-INVALID-STATE)
    (asserts! (is-participant tx-sender (get buyer escrow-data) (get seller escrow-data)) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get funded-amount escrow-data) u0) ERR-ALREADY-EXISTS)
    (asserts! (not (is-escrow-expired escrow-data)) ERR-EXPIRED)
    
    ;; Transfer STX to contract
    (try! (stx-transfer? (get amount escrow-data) tx-sender (as-contract tx-sender)))
    
    ;; Record deposit
    (map-set deposits
      { escrow-id: escrow-id }
      { 
        depositor: tx-sender, 
        amount: (get amount escrow-data), 
        timestamp: block-height,
        block-height: block-height
      }
    )
    
    ;; Update escrow status
    (map-set escrows
      { id: escrow-id }
      (merge escrow-data { 
        status: "funded", 
        funded-amount: (get amount escrow-data),
        last-activity: block-height
      })
    )
    
    ;; Add transaction record
    (add-transaction-record escrow-id "funded" none)
    
    ;; Update total volume
    (var-set total-volume (+ (var-get total-volume) (get amount escrow-data)))
    
    (ok true)
  )
)

;; Confirm completion by buyer or seller
(define-public (confirm-completion (escrow-id uint))
  (let ((escrow-data (unwrap! (map-get? escrows { id: escrow-id }) ERR-NOT-FOUND)))
    
    ;; Validations
    (asserts! (not (is-contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (is-eq (get status escrow-data) "funded") ERR-INVALID-STATE)
    (asserts! (is-participant tx-sender (get buyer escrow-data) (get seller escrow-data)) ERR-UNAUTHORIZED)
    (asserts! (not (is-escrow-expired escrow-data)) ERR-EXPIRED)
    
    ;; Update confirmation status
    (let ((updated-escrow 
            (if (is-eq tx-sender (get buyer escrow-data))
                (merge escrow-data { buyer-confirmed: true, last-activity: block-height })
                (merge escrow-data { seller-confirmed: true, last-activity: block-height }))))
      
      (map-set escrows { id: escrow-id } updated-escrow)
      
      ;; Add transaction record
      (add-transaction-record escrow-id "confirmed" none)
      
      ;; Check if both confirmed and release funds
      (if (and (get buyer-confirmed updated-escrow) (get seller-confirmed updated-escrow))
          (begin
            (map-set escrows { id: escrow-id } (merge updated-escrow { status: "completed" }))
            (try! (release-funds-to-seller escrow-id))
            (ok true)
          )
          (ok true)
      )
    )
  )
)

;; Release funds to seller (private function)
(define-private (release-funds-to-seller (escrow-id uint))
  (let ((escrow-data (unwrap! (map-get? escrows { id: escrow-id }) ERR-NOT-FOUND))
        (arbiter-data (unwrap! (map-get? arbiters { arbiter: (get arbiter escrow-data) }) ERR-NOT-FOUND)))
    
    (let ((total-amount (get funded-amount escrow-data))
          (protocol-fee-amt (calculate-protocol-fee total-amount))
          (arbiter-fee-amt (calculate-arbiter-fee total-amount (get fee-rate arbiter-data)))
          (seller-amount (- total-amount protocol-fee-amt arbiter-fee-amt)))
      
      ;; Ensure we have enough funds
      (asserts! (>= total-amount (+ protocol-fee-amt arbiter-fee-amt)) ERR-INSUFFICIENT-FUNDS)
      
      ;; Transfer protocol fee if > 0
      (if (> protocol-fee-amt u0)
          (try! (as-contract (stx-transfer? protocol-fee-amt tx-sender (var-get fee-recipient))))
          true
      )
      
      ;; Transfer arbiter fee if > 0
      (if (> arbiter-fee-amt u0)
          (try! (as-contract (stx-transfer? arbiter-fee-amt tx-sender (get arbiter escrow-data))))
          true
      )
      
      ;; Transfer remaining to seller if > 0
      (if (> seller-amount u0)
          (try! (as-contract (stx-transfer? seller-amount tx-sender (get seller escrow-data))))
          true
      )
      
      ;; Add transaction record
      (add-transaction-record escrow-id "completed" none)
      
      (ok true)
    )
  )
)

;; File dispute with detailed reason
(define-public (file-dispute (escrow-id uint) (reason (string-utf8 256)))
  (let ((escrow-data (unwrap! (map-get? escrows { id: escrow-id }) ERR-NOT-FOUND)))
    
    ;; Validations
    (asserts! (not (is-contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (is-eq (get status escrow-data) "funded") ERR-INVALID-STATE)
    (asserts! (is-participant tx-sender (get buyer escrow-data) (get seller escrow-data)) ERR-UNAUTHORIZED)
    (asserts! (validate-dispute-reason reason) ERR-INVALID-PARAMS)
    (asserts! (not (is-escrow-expired escrow-data)) ERR-EXPIRED)
    
    ;; Update escrow with dispute
    (map-set escrows
      { id: escrow-id }
      (merge escrow-data { 
        status: "disputed", 
        dispute-reason: (some reason),
        last-activity: block-height
      })
    )
    
    ;; Add transaction record
    (add-transaction-record escrow-id "disputed" (some reason))
    
    (ok true)
  )
)

;; Resolve dispute (arbiter only) with percentage-based distribution
(define-public (resolve-dispute (escrow-id uint) (buyer-percentage uint))
  (let ((escrow-data (unwrap! (map-get? escrows { id: escrow-id }) ERR-NOT-FOUND))
        (arbiter-data (unwrap! (map-get? arbiters { arbiter: tx-sender }) ERR-NOT-FOUND)))
    
    ;; Validations
    (asserts! (not (is-contract-paused)) ERR-CONTRACT-PAUSED)
    (asserts! (is-eq tx-sender (get arbiter escrow-data)) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get status escrow-data) "disputed") ERR-INVALID-STATE)
    (asserts! (<= buyer-percentage PERCENTAGE-PRECISION) ERR-INVALID-PERCENTAGE)
    
    ;; Calculate distribution
    (let ((total-amount (get funded-amount escrow-data))
          (protocol-fee-amt (calculate-protocol-fee total-amount))
          (arbiter-fee-amt (calculate-arbiter-fee total-amount (get fee-rate arbiter-data)))
          (remaining-amount (- total-amount protocol-fee-amt arbiter-fee-amt))
          (buyer-amount (/ (* remaining-amount buyer-percentage) PERCENTAGE-PRECISION))
          (seller-amount (- remaining-amount buyer-amount)))
      
      ;; Ensure valid amounts
      (asserts! (>= total-amount (+ protocol-fee-amt arbiter-fee-amt)) ERR-INSUFFICIENT-FUNDS)
      
      ;; Distribute funds
      ;; Protocol fee
      (if (> protocol-fee-amt u0)
          (try! (as-contract (stx-transfer? protocol-fee-amt tx-sender (var-get fee-recipient))))
          true
      )
      
      ;; Arbiter fee
      (if (> arbiter-fee-amt u0)
          (try! (as-contract (stx-transfer? arbiter-fee-amt tx-sender tx-sender)))
          true
      )
      
      ;; Buyer share
      (if (> buyer-amount u0)
          (try! (as-contract (stx-transfer? buyer-amount tx-sender (get buyer escrow-data))))
          true
      )
      
      ;; Seller share  
      (if (> seller-amount u0)
          (try! (as-contract (stx-transfer? seller-amount tx-sender (get seller escrow-data))))
          true
      )
      
      ;; Update escrow status
      (map-set escrows { id: escrow-id } (merge escrow-data { status: "resolved", last-activity: block-height }))
      
      ;; Update arbiter stats
      (let ((disputes-won-buyer (if (> buyer-percentage u5000) (+ (get disputes-won-buyer arbiter-data) u1) (get disputes-won-buyer arbiter-data)))
            (disputes-won-seller (if (<= buyer-percentage u5000) (+ (get disputes-won-seller arbiter-data) u1) (get disputes-won-seller arbiter-data))))
        
        (map-set arbiters 
          { arbiter: tx-sender }
          (merge arbiter-data { 
            disputes-resolved: (+ (get disputes-resolved arbiter-data) u1),
            disputes-won-buyer: disputes-won-buyer,
            disputes-won-seller: disputes-won-seller,
            last-activity: block-height
          })
        )
      )
      
      ;; Add transaction record
      (add-transaction-record escrow-id "resolved" none)
      
      (ok true)
    )
  )
)

;; Refund escrow (if expired or unfunded cancellation)
(define-public (refund-escrow (escrow-id uint))
  (let ((escrow-data (unwrap! (map-get? escrows { id: escrow-id }) ERR-NOT-FOUND)))
    
    ;; Check refund conditions
    (let ((is-expired (is-escrow-expired escrow-data))
          (is-unfunded (is-eq (get status escrow-data) "created"))
          (is-creator (is-eq tx-sender (get creator escrow-data))))
      
      (asserts! (or is-expired (and is-unfunded is-creator)) ERR-INVALID-STATE)
      
      ;; If funded, refund the depositor
      (if (> (get funded-amount escrow-data) u0)
          (let ((deposit-data (unwrap! (map-get? deposits { escrow-id: escrow-id }) ERR-NOT-FOUND)))
            (try! (as-contract (stx-transfer? (get amount deposit-data) tx-sender (get depositor deposit-data))))
          )
          true
      )
      
      ;; Update status
      (map-set escrows { id: escrow-id } (merge escrow-data { status: "refunded", last-activity: block-height }))
      
      ;; Add transaction record
      (add-transaction-record escrow-id "refunded" none)
      
      (ok true)
    )
  )
)

;; Emergency functions (contract owner only)
(define-public (emergency-pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set emergency-mode true)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (emergency-unpause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set emergency-mode false)
    (var-set contract-paused false)
    (ok true)
  )
)

;; Admin functions
(define-public (pause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set contract-paused true)
    (ok true)
  )
)

(define-public (unpause-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (not (is-emergency-mode)) ERR-CONTRACT-PAUSED)
    (var-set contract-paused false)
    (ok true)
  )
)

(define-public (update-protocol-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (<= new-fee MAX-PROTOCOL-FEE) ERR-INVALID-PARAMS)
    (var-set protocol-fee new-fee)
    (ok true)
  )
)

(define-public (update-fee-recipient (new-recipient principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (asserts! (is-valid-principal new-recipient) ERR-INVALID-PARAMS)
    (var-set fee-recipient new-recipient)
    (ok true)
  )
)

;; Read-only functions for querying contract state
(define-read-only (get-escrow (escrow-id uint))
  (map-get? escrows { id: escrow-id })
)

(define-read-only (get-arbiter (arbiter principal))
  (map-get? arbiters { arbiter: arbiter })
)

(define-read-only (get-deposit (escrow-id uint))
  (map-get? deposits { escrow-id: escrow-id })
)

(define-read-only (get-participant-role (escrow-id uint) (participant principal))
  (map-get? escrow-participants { escrow-id: escrow-id, participant: participant })
)

(define-read-only (get-transaction-history (escrow-id uint) (sequence uint))
  (map-get? transaction-history { escrow-id: escrow-id, sequence: sequence })
)

(define-read-only (get-contract-info)
  {
    paused: (var-get contract-paused),
    emergency-mode: (var-get emergency-mode),
    protocol-fee: (var-get protocol-fee),
    fee-recipient: (var-get fee-recipient),
    next-escrow-id: (var-get next-escrow-id),
    total-escrows-created: (var-get total-escrows-created),
    total-volume: (var-get total-volume),
    owner: CONTRACT-OWNER
  }
)

(define-read-only (get-protocol-fee)
  (var-get protocol-fee)
)

(define-read-only (get-next-escrow-id)
  (var-get next-escrow-id)
)

(define-read-only (get-contract-stats)
  {
    total-escrows: (var-get total-escrows-created),
    total-volume: (var-get total-volume),
    protocol-fee-rate: (var-get protocol-fee),
    is-paused: (var-get contract-paused),
    is-emergency: (var-get emergency-mode)
  }
)
