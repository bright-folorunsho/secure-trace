;; Title: SecureTrace
;; 
;; Summary: Decentralized security audit verification protocol built on Bitcoin's Layer 2
;;
;; Description: SecureTrace establishes an immutable reputation layer for smart contract 
;; security auditors on the Stacks blockchain. By leveraging Bitcoin's settlement finality,
;; the protocol creates transparent audit trails, incentivizes thorough security reviews,
;; and builds verifiable trust through peer validation. Auditors stake their reputation with
;; each submission, while certified validators ensure quality control-transforming security
;; auditing into a cryptographically verifiable public good that strengthens Bitcoin's 
;; expanding smart contract ecosystem.

;; CONSTANTS

(define-constant SYSTEM_ADMIN tx-sender)

;; Error codes
(define-constant ERR_PERMISSION_DENIED (err u300))
(define-constant ERR_AUDIT_NOT_EXISTS (err u301))
(define-constant ERR_REVIEWER_REGISTERED (err u302))
(define-constant ERR_INVALID_REVIEWER (err u303))
(define-constant ERR_PAYMENT_FAILED (err u304))
(define-constant ERR_SYSTEM_INACTIVE (err u305))

;; DATA VARIABLES

(define-data-var audit-id-counter uint u0)
(define-data-var verification-cost uint u3000000) ;; 3 STX in microSTX
(define-data-var system-enabled bool true)
(define-data-var total-audits-completed uint u0)

;; DATA MAPS

(define-map audit-records
    { audit-identifier: uint }
    {
        contract-principal: principal,
        reviewer-address: principal,
        creation-block: uint,
        vulnerability-level: uint,
        findings-count: uint,
        evidence-hash: (string-ascii 64),
        validation-status: bool,
        quality-rating: uint,
        audit-category: (string-ascii 20)
    }
)

(define-map code-reviewers
    { reviewer-address: principal }
    {
        credibility-score: uint,
        total-reviews: uint,
        validated-reviews: uint,
        reviewer-status: bool,
        expertise-level: uint,
        review-earnings: uint
    }
)

(define-map contract-audit-history
    { contract-principal: principal }
    {
        latest-audit-id: uint,
        audit-frequency: uint,
        top-quality-score: uint,
        last-review-block: uint,
        total-findings: uint
    }
)

(define-map certified-reviewers principal bool)
(define-map reviewer-revenue principal uint)
(define-map audit-categories (string-ascii 20) uint)

;; PUBLIC FUNCTIONS - REVIEWER MANAGEMENT

;; Register as a security auditor in the protocol
(define-public (register-reviewer)
    (let ((caller tx-sender))
        (asserts! (var-get system-enabled) ERR_SYSTEM_INACTIVE)
        (asserts! (is-none (map-get? code-reviewers { reviewer-address: caller })) ERR_REVIEWER_REGISTERED)
        (map-set code-reviewers 
            { reviewer-address: caller }
            {
                credibility-score: u0,
                total-reviews: u0,
                validated-reviews: u0,
                reviewer-status: true,
                expertise-level: u1,
                review-earnings: u0
            }
        )
        (ok true)
    )
)

;; Temporarily suspend own reviewer account
(define-public (suspend-reviewer-account)
    (let (
        (caller tx-sender)
        (reviewer-data (unwrap! (map-get? code-reviewers { reviewer-address: caller }) ERR_INVALID_REVIEWER))
    )
        (map-set code-reviewers
            { reviewer-address: caller }
            (merge reviewer-data { reviewer-status: false })
        )
        (ok true)
    )
)

;; Reactivate suspended reviewer account
(define-public (reactivate-reviewer-account)
    (let (
        (caller tx-sender)
        (reviewer-data (unwrap! (map-get? code-reviewers { reviewer-address: caller }) ERR_INVALID_REVIEWER))
    )
        (asserts! (var-get system-enabled) ERR_SYSTEM_INACTIVE)
        (map-set code-reviewers
            { reviewer-address: caller }
            (merge reviewer-data { reviewer-status: true })
        )
        (ok true)
    )
)

;; Update self-assessed expertise level (max: 10)
(define-public (update-expertise-level (new-level uint))
    (let (
        (caller tx-sender)
        (reviewer-data (unwrap! (map-get? code-reviewers { reviewer-address: caller }) ERR_INVALID_REVIEWER))
    )
        (asserts! (<= new-level u10) ERR_PERMISSION_DENIED)
        (map-set code-reviewers
            { reviewer-address: caller }
            (merge reviewer-data { expertise-level: new-level })
        )
        (ok true)
    )
)

;; PUBLIC FUNCTIONS - AUDIT SUBMISSION

;; Submit a comprehensive security audit report
(define-public (submit-audit 
    (contract-principal principal) 
    (vulnerability-level uint) 
    (findings-count uint) 
    (evidence-hash (string-ascii 64)) 
    (quality-rating uint) 
    (audit-category (string-ascii 20)))
    (let (
        (caller tx-sender)
        (new-audit-id (+ (var-get audit-id-counter) u1))
        (reviewer-data (unwrap! (map-get? code-reviewers { reviewer-address: caller }) ERR_INVALID_REVIEWER))
    )
        ;; Validate system and reviewer status
        (asserts! (var-get system-enabled) ERR_SYSTEM_INACTIVE)
        (asserts! (get reviewer-status reviewer-data) ERR_INVALID_REVIEWER)
        
        ;; Process audit fee payment
        (try! (stx-transfer? (var-get verification-cost) caller SYSTEM_ADMIN))
        
        ;; Create audit record
        (map-set audit-records
            { audit-identifier: new-audit-id }
            {
                contract-principal: contract-principal,
                reviewer-address: caller,
                creation-block: stacks-block-height,
                vulnerability-level: vulnerability-level,
                findings-count: findings-count,
                evidence-hash: evidence-hash,
                validation-status: false,
                quality-rating: quality-rating,
                audit-category: audit-category
            }
        )
        
        ;; Update reviewer statistics
        (map-set code-reviewers
            { reviewer-address: caller }
            (merge reviewer-data { 
                total-reviews: (+ (get total-reviews reviewer-data) u1),
                review-earnings: (+ (get review-earnings reviewer-data) (var-get verification-cost))
            })
        )
        
        ;; Update contract audit history
        (let ((contract-history (default-to 
                { latest-audit-id: u0, audit-frequency: u0, top-quality-score: u0, last-review-block: u0, total-findings: u0 }
                (map-get? contract-audit-history { contract-principal: contract-principal })
            )))
            (map-set contract-audit-history
                { contract-principal: contract-principal }
                {
                    latest-audit-id: new-audit-id,
                    audit-frequency: (+ (get audit-frequency contract-history) u1),
                    top-quality-score: (if (> quality-rating (get top-quality-score contract-history)) 
                                       quality-rating 
                                       (get top-quality-score contract-history)),
                    last-review-block: stacks-block-height,
                    total-findings: (+ (get total-findings contract-history) findings-count)
                }
            )
        )
        
        ;; Track reviewer revenue
        (let ((current-revenue (default-to u0 (map-get? reviewer-revenue caller))))
            (map-set reviewer-revenue caller (+ current-revenue (var-get verification-cost)))
        )
        
        ;; Update category statistics
        (let ((category-count (default-to u0 (map-get? audit-categories audit-category))))
            (map-set audit-categories audit-category (+ category-count u1))
        )
        
        ;; Update global counters
        (var-set audit-id-counter new-audit-id)
        (var-set total-audits-completed (+ (var-get total-audits-completed) u1))
        
        (ok new-audit-id)
    )
)

;; PUBLIC FUNCTIONS - AUDIT VALIDATION

;; Validate audit quality and accuracy (certified reviewers only)
(define-public (validate-audit (audit-identifier uint))
    (let (
        (caller tx-sender)
        (audit-data (unwrap! (map-get? audit-records { audit-identifier: audit-identifier }) ERR_AUDIT_NOT_EXISTS))
        (original-reviewer (get reviewer-address audit-data))
    )
        ;; Ensure validator is certified and not self-validating
        (asserts! (default-to false (map-get? certified-reviewers caller)) ERR_PERMISSION_DENIED)
        (asserts! (not (is-eq caller original-reviewer)) ERR_PERMISSION_DENIED)
        
        ;; Mark audit as validated
        (map-set audit-records
            { audit-identifier: audit-identifier }
            (merge audit-data { validation-status: true })
        )
        
        ;; Boost original reviewer's reputation
        (let ((reviewer-data (unwrap! (map-get? code-reviewers { reviewer-address: original-reviewer }) ERR_AUDIT_NOT_EXISTS)))
            (map-set code-reviewers
                { reviewer-address: original-reviewer }
                (merge reviewer-data { 
                    validated-reviews: (+ (get validated-reviews reviewer-data) u1),
                    credibility-score: (+ (get credibility-score reviewer-data) u20),
                    expertise-level: (+ (get expertise-level reviewer-data) u1)
                })
            )
        )
        
        (ok true)
    )
)

;; PUBLIC FUNCTIONS - ADMIN CONTROLS

;; Grant certification status to trusted reviewers
(define-public (certify-reviewer (reviewer principal))
    (begin
        (asserts! (is-eq tx-sender SYSTEM_ADMIN) ERR_PERMISSION_DENIED)
        (map-set certified-reviewers reviewer true)
        (ok true)
    )
)

;; Adjust audit submission fee
(define-public (modify-verification-cost (new-cost uint))
    (begin
        (asserts! (is-eq tx-sender SYSTEM_ADMIN) ERR_PERMISSION_DENIED)
        (var-set verification-cost new-cost)
        (ok true)
    )
)

;; Enable or disable protocol operations
(define-public (toggle-system-status)
    (begin
        (asserts! (is-eq tx-sender SYSTEM_ADMIN) ERR_PERMISSION_DENIED)
        (var-set system-enabled (not (var-get system-enabled)))
        (ok (var-get system-enabled))
    )
)

;; READ-ONLY FUNCTIONS - AUDIT DATA

;; Retrieve complete audit record by ID
(define-read-only (get-audit-record (audit-identifier uint))
    (map-get? audit-records { audit-identifier: audit-identifier })
)

;; Get most recent audit for a specific contract
(define-read-only (get-most-recent-audit (contract-principal principal))
    (let ((contract-history (map-get? contract-audit-history { contract-principal: contract-principal })))
        (match contract-history
            summary (map-get? audit-records { audit-identifier: (get latest-audit-id summary) })
            none
        )
    )
)

;; Get comprehensive audit history for a contract
(define-read-only (get-audit-summary (contract-principal principal))
    (map-get? contract-audit-history { contract-principal: contract-principal })
)

;; Get total number of audits submitted
(define-read-only (get-audit-counter)
    (var-get audit-id-counter)
)

;; Get system-wide audit completion statistics
(define-read-only (get-total-audits-completed)
    (var-get total-audits-completed)
)

;; Get audit count by category
(define-read-only (get-category-stats (category (string-ascii 20)))
    (default-to u0 (map-get? audit-categories category))
)

;; READ-ONLY FUNCTIONS - REVIEWER DATA

;; Get complete reviewer profile and statistics
(define-read-only (get-reviewer-profile (reviewer-address principal))
    (map-get? code-reviewers { reviewer-address: reviewer-address })
)

;; Check if reviewer has certification status
(define-read-only (is-certified-reviewer (reviewer principal))
    (default-to false (map-get? certified-reviewers reviewer))
)

;; Get total earnings for a reviewer
(define-read-only (get-reviewer-revenue (reviewer principal))
    (default-to u0 (map-get? reviewer-revenue reviewer))
)

;; Get sample reviewer data for reputation queries
(define-read-only (get-top-reviewer-sample (reviewer principal))
    (let ((reviewer-data (map-get? code-reviewers { reviewer-address: reviewer })))
        (match reviewer-data
            data (some {
                address: reviewer,
                credibility: (get credibility-score data),
                total-reviews: (get total-reviews data),
                expertise: (get expertise-level data)
            })
            none
        )
    )
)

;; READ-ONLY FUNCTIONS - SYSTEM INFO

;; Get current audit submission fee
(define-read-only (get-verification-cost)
    (var-get verification-cost)
)

;; Check if protocol is currently operational
(define-read-only (is-system-enabled)
    (var-get system-enabled)
)

;; Get protocol administrator address
(define-read-only (get-system-admin)
    SYSTEM_ADMIN
)