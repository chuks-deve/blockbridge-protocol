;; Blockchain Bridge Protocol
;; The protocol for managing peer-to-peer transfers across different systems

;; Protocol Management and Error Constants
(define-constant PROTOCOL_CONTROLLER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_RECORD_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_HANDLED (err u102))
(define-constant ERR_OPERATION_FAILED (err u103))
(define-constant ERR_INVALID_ID (err u104))
(define-constant ERR_INVALID_PARAMETERS (err u105))
(define-constant ERR_INVALID_USER (err u106))
(define-constant ERR_TIMEFRAME_EXPIRED (err u107))
(define-constant PROTOCOL_WINDOW_BLOCKS u1008) ;; Approximately 7 days window



;; Core Protocol Record Storage
(define-map BridgeOperations
  { operation-id: uint }
  {
    source-entity: principal,
    destination-entity: principal,
    resource-category: uint,
    allocation-quantity: uint,
    operation-state: (string-ascii 10),
    inception-block: uint,
    window-end-block: uint
  }
)

;; Operation Tracker
(define-data-var current-operation-id uint u0)

;; -------------------------------------------------------------
;; Protocol Validation Functions
;; -------------------------------------------------------------

;; Validate Entity Uniqueness
(define-private (validate-entity-uniqueness (entity principal))
  (and 
    (not (is-eq entity tx-sender))
    (not (is-eq entity (as-contract tx-sender)))
  )
)

;; Validate Operation Identifier
(define-private (validate-operation-id (operation-id uint))
  (<= operation-id (var-get current-operation-id))
)

;; Recover Expired Operation Resources
(define-public (recover-expired-operation (operation-id uint))
  (begin
    (asserts! (validate-operation-id operation-id) ERR_INVALID_ID)
    (let
      (
        (operation-data (unwrap! (map-get? BridgeOperations { operation-id: operation-id }) ERR_RECORD_NOT_FOUND))
        (source (get source-entity operation-data))
        (allocation (get allocation-quantity operation-data))
        (end-block (get window-end-block operation-data))
      )
      (asserts! (or (is-eq tx-sender source) (is-eq tx-sender PROTOCOL_CONTROLLER)) ERR_UNAUTHORIZED)
      (asserts! (or (is-eq (get operation-state operation-data) "pending") (is-eq (get operation-state operation-data) "accepted")) ERR_ALREADY_HANDLED)
      (asserts! (> block-height end-block) (err u108)) ;; Must be expired
      (match (as-contract (stx-transfer? allocation tx-sender source))
        success
          (begin
            (map-set BridgeOperations
              { operation-id: operation-id }
              (merge operation-data { operation-state: "expired" })
            )
            (print {event: "operation_expired_recovered", operation-id: operation-id, source: source, allocation: allocation})
            (ok true)
          )
        error ERR_OPERATION_FAILED
      )
    )
  )
)

;; Begin Resolution Process
(define-public (begin-resolution-process (operation-id uint) (resolution-justification (string-ascii 50)))
  (begin
    (asserts! (validate-operation-id operation-id) ERR_INVALID_ID)
    (let
      (
        (operation-data (unwrap! (map-get? BridgeOperations { operation-id: operation-id }) ERR_RECORD_NOT_FOUND))
        (source (get source-entity operation-data))
        (destination (get destination-entity operation-data))
      )
      (asserts! (or (is-eq tx-sender source) (is-eq tx-sender destination)) ERR_UNAUTHORIZED)
      (asserts! (or (is-eq (get operation-state operation-data) "pending") (is-eq (get operation-state operation-data) "accepted")) ERR_ALREADY_HANDLED)
      (asserts! (<= block-height (get window-end-block operation-data)) ERR_TIMEFRAME_EXPIRED)
      (map-set BridgeOperations
        { operation-id: operation-id }
        (merge operation-data { operation-state: "disputed" })
      )
      (print {event: "operation_disputed", operation-id: operation-id, initiator: tx-sender, justification: resolution-justification})
      (ok true)
    )
  )
)

;; Add Verification Hash
(define-public (add-verification-hash (operation-id uint) (hash-proof (buff 65)))
  (begin
    (asserts! (validate-operation-id operation-id) ERR_INVALID_ID)
    (let
      (
        (operation-data (unwrap! (map-get? BridgeOperations { operation-id: operation-id }) ERR_RECORD_NOT_FOUND))
        (source (get source-entity operation-data))
        (destination (get destination-entity operation-data))
      )
      (asserts! (or (is-eq tx-sender source) (is-eq tx-sender destination)) ERR_UNAUTHORIZED)
      (asserts! (or (is-eq (get operation-state operation-data) "pending") (is-eq (get operation-state operation-data) "accepted")) ERR_ALREADY_HANDLED)
      (print {event: "hash_verification_added", operation-id: operation-id, verifier: tx-sender, hash: hash-proof})
      (ok true)
    )
  )
)

;; Register Contingency Contact
(define-public (register-contingency-contact (operation-id uint) (contingency-contact principal))
  (begin
    (asserts! (validate-operation-id operation-id) ERR_INVALID_ID)
    (let
      (
        (operation-data (unwrap! (map-get? BridgeOperations { operation-id: operation-id }) ERR_RECORD_NOT_FOUND))
        (source (get source-entity operation-data))
      )
      (asserts! (is-eq tx-sender source) ERR_UNAUTHORIZED)
      (asserts! (not (is-eq contingency-contact tx-sender)) (err u111)) ;; Contact must differ
      (asserts! (is-eq (get operation-state operation-data) "pending") ERR_ALREADY_HANDLED)
      (print {event: "contingency_contact_registered", operation-id: operation-id, source: source, contact: contingency-contact})
      (ok true)
    )
  )
)

;; Moderate Disputed Operation
(define-public (moderate-operation (operation-id uint) (distribution-ratio uint))
  (begin
    (asserts! (validate-operation-id operation-id) ERR_INVALID_ID)
    (asserts! (is-eq tx-sender PROTOCOL_CONTROLLER) ERR_UNAUTHORIZED)
    (asserts! (<= distribution-ratio u100) ERR_INVALID_PARAMETERS) ;; Ratio must be 0-100
    (let
      (
        (operation-data (unwrap! (map-get? BridgeOperations { operation-id: operation-id }) ERR_RECORD_NOT_FOUND))
        (source (get source-entity operation-data))
        (destination (get destination-entity operation-data))
        (allocation (get allocation-quantity operation-data))
        (destination-portion (/ (* allocation distribution-ratio) u100))
        (source-portion (- allocation destination-portion))
      )
      (asserts! (is-eq (get operation-state operation-data) "disputed") (err u112)) ;; Must be disputed
      (asserts! (<= block-height (get window-end-block operation-data)) ERR_TIMEFRAME_EXPIRED)

      ;; Transfer destination portion
      (unwrap! (as-contract (stx-transfer? destination-portion tx-sender destination)) ERR_OPERATION_FAILED)

      ;; Transfer source portion
      (unwrap! (as-contract (stx-transfer? source-portion tx-sender source)) ERR_OPERATION_FAILED)

      (map-set BridgeOperations
        { operation-id: operation-id }
        (merge operation-data { operation-state: "moderated" })
      )
      (print {event: "operation_moderated", operation-id: operation-id, source: source, destination: destination, 
              destination-portion: destination-portion, source-portion: source-portion, distribution-ratio: distribution-ratio})
      (ok true)
    )
  )
)
