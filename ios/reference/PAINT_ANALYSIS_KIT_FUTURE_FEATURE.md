# Future Feature: Paint Sample Collection Kit + Lab Partnership

**Status: DEFERRED.** Not being built now. Sean raised this 2026-07 while
reviewing the v1 scope decision ("investigative documentation + leads
tool") and explicitly said: *"maybe we add the paint analysis later, but
lets develope with that feature to be added later"* — i.e., reserve room
for it architecturally, don't implement it yet.

This doc exists so that whoever (Claw or AI Developer) picks this up later
doesn't have to re-derive the requirements from scratch.

---

## 1. What Sean asked for (verbatim intent)

> "should we make it easy for user to collect paint that was transferred to
> their vehicle and have some business relationship with a company who can
> analyse the paint should a user want to pay the fee to have it analysed?
> this should include detailed directions on how to collect and send for
> analysis. We should have an internal way to track the testing within our
> app via a code to track similar to any DNA testing apps"

Four distinct pieces:

1. **In-app collection instructions** — step-by-step guidance for a
   non-professional user to physically collect a paint-transfer sample
   from their damaged vehicle.
2. **A business relationship with a paint-analysis lab** — a real partner
   company that does chemical/spectroscopic paint analysis (this is a
   different, more rigorous kind of analysis than anything the app does
   today — the app only does photographic Delta-E color-distance
   comparison, not lab chemistry).
3. **A paid service flow** — user pays a fee in-app to have their
   physical sample analyzed by the partner lab.
4. **A DNA-kit-style tracking system** — unique code per kit, status
   pipeline, results delivered back into the case.

## 2. Why this was deferred instead of built immediately

Same reasoning pattern as the "2 open design questions" and the "tech
stack / ballistics" discussion earlier in this project: this feature has
real-world dependencies that can't be resolved by writing code —

- **No lab partner is under contract yet.** Until one exists we don't know
  their intake process, turnaround time, results format, or whether they
  expose an API vs. requiring manual coordination.
- **No payment processor is wired up.** Needs a decision (Stripe is the
  natural fit given Cloudflare Workers backend elsewhere in this
  ecosystem) plus a pricing model (flat fee vs. tiered).
- **Real chain-of-custody / legal exposure.** This is arguably the most
  legally delicate feature discussed in this entire project: we'd be
  giving non-professionals instructions for collecting what may become
  evidence in a legal proceeding. That has to be worded very carefully —
  in the same spirit as the disclaimer language just added to
  `MatchResult.disclaimerText` — so we're not implying courtroom-grade
  sample integrity we can't actually back up.
- **Needs real backend persistence.** Kit records, payment status, and
  lab status updates can't live only on-device (a lab or a webhook needs
  to be able to update a kit's status independent of the user's phone).
  This app is otherwise local-storage-first (see `StorageService.swift`);
  this feature would be the first thing in the project that requires a
  server component (Cloudflare D1 + Worker API routes, most likely).

Building UI/payment/backend now, before those are resolved, would very
likely mean throwing it away or heavily reworking it once real answers
exist — the same trap the `auditLog` field fell into (promised in docs,
built to a guess, had to be retrofitted). So instead we've only reserved
the data-model shape (see below) and written down the open questions.

## 3. What WAS done now (schema reservation only)

- **`Models/PaintSampleKit.swift`** (new file) — defines `PaintSampleKit`
  struct + `PaintSampleKitStatus` enum modeled on a 23andMe/AncestryDNA-style
  pipeline: `requested -> registered -> mailed -> receivedByLab ->
  inAnalysis -> resultsReady` (+ `cancelled`). Includes fields for
  `kitCode`, dates per stage, `partnerLabName`, `resultsSummary` /
  `resultsReportURL`, and minimal payment tracking (`feeAmountUSD`,
  `paymentReference`).
- **`Models/Vehicle.swift`** — added `var paintSampleKit: PaintSampleKit?`
  to `DamageZone`, defaulting to `nil`. Because it's Optional and
  `DamageZone` still uses fully compiler-synthesized `Codable` (no custom
  `init(from:)`), this is a safe additive change: old persisted case JSON
  without this field decodes fine automatically, no migration code needed.

**Nothing else changed.** No UI screen references `PaintSampleKit`, no
ViewModel creates or mutates one, no backend exists. It is intentionally
unreachable/dead code until the real feature is greenlit — this is purely
about not having to fight the JSON schema later.

## 4. Open questions to resolve before implementation starts

Same list posed to Sean 2026-07, still unanswered — resolve these first:

1. **Lab partner** — Specific paint-forensics lab already in mind, or
   design generic/swappable? Do they have an API, or is this initially
   "we collect payment + shipping info, then manually courier samples /
   email the lab"?
2. **Payment** — Stripe (fits the existing Cloudflare Workers pattern used
   elsewhere)? Flat fee vs. tiered by turnaround time? Does money flow
   through us (we then pay the lab) or are we a referral/booking layer
   only (lab bills the customer directly)?
3. **Tracking-code model** — Confirm the DNA-kit-style multi-stage
   pipeline above matches what Sean wants, vs. something simpler (e.g.
   just a reference number with no status pipeline).
4. **Collection instructions & liability framing** — Confirm we frame
   in-app collection instructions as "best-effort, not accredited
   chain-of-custody" (mirroring the disclaimer language already added
   to match/report output), rather than attempting real evidentiary rigor
   (tamper-evident bag photography, GPS/timestamp capture, witness
   signature, etc.) — that would be a much bigger scope.
5. **Backend** — Confirm this project should grow a Cloudflare D1 +
   Worker API backend (`paint_sample_kits` table, kit-creation /
   status-lookup / webhook-receiver routes) for this feature, rather than
   hooking into some other existing backend service Sean already has.

## 5. Rough shape of the eventual implementation (for planning only —
## not started)

- **Data model**: `PaintSampleKit` (done, see above) + a
  `PaintSampleKitService` for status transitions.
- **Backend**: Cloudflare D1 table for kits (keyed by `kitCode`), Worker
  routes: `POST /api/kits` (create + payment), `GET /api/kits/:code`
  (status lookup), `POST /api/kits/:code/status` (lab or admin update,
  auth-gated).
- **iOS UI**: a new flow off `DamageZone` detail — "Send this damage for
  lab paint analysis" -> collection instructions (illustrated
  step-by-step) -> payment sheet -> kit code + shipping label/address ->
  status tracker screen (polls or is pushed the kit's current status) ->
  results view once `resultsReady`.
- **Audit trail integration**: each kit status change should likely also
  call `ForensicCase.recordAudit(...)` (new `AuditAction` cases would be
  needed, e.g. `.paintKitRequested`, `.paintKitStatusUpdated`) so it shows
  up in the existing chain-of-custody log and PDF report.
- **Report integration**: `PDFReportGenerator` would need a new section
  for lab results once available, worded consistently with the v1
  disclaimer language (results support investigation, are not themselves
  being asserted as courtroom-certified until/unless the partner lab's own
  accreditation supports that claim).

## 6. Decision log

- **2026-07** — Sean requested the feature; AI Developer proposed 5
  clarifying questions before building; Sean responded to defer full
  implementation but develop with the feature "to be added later" in mind
  → schema reservation (`PaintSampleKit.swift`, `DamageZone.paintSampleKit`)
  added, this doc written, no UI/payment/backend built.
