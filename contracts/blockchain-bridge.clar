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
