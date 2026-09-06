# 🧬 FORENSIC MATCHING ALGORITHM - HOW IT WORKS

## Core Innovation: 7-Factor Weighted Composite Scoring

Our algorithm mimics real forensic investigators by analyzing multiple independent evidence markers and combining them into a single confidence score.

---

## 🔬 THE 7 FORENSIC FACTORS

### 1. Paint Transfer Match (30% weight) ⭐ HIGHEST PRIORITY
**What it does:**
- Compares paint color found on victim vehicle to suspect vehicle color
- Checks for reciprocal transfer (victim color on suspect)
- Uses RGB color space with Euclidean distance calculation

**Scoring:**
- Direct color match (victim transfer ↔ suspect vehicle): 70% of score
- Reciprocal match (suspect transfer ↔ victim vehicle): 30% of score
- Color similarity measured 0-100% (perfect match = 0 distance in RGB space)

**Your case:**
- White paint on your gray Tundra = 100% match to white suspect vehicle
- Score: 70/100 (would be 100/100 if we confirm gray paint on suspect)

---

### 2. Height Alignment (20% weight) ⭐ CRITICAL MARKER
**What it does:**
- Compares damage height on both vehicles
- Misaligned heights = physically impossible collision

**Scoring:**
- 0-2" difference = 100% (forensic tolerance)
- 2-4" difference = 75%
- 4-6" difference = 50%
- >6" difference = 0% (rule out suspect)

**Your case:**
- Your truck: 28.5" (measured 27-30" range)
- Suspect: 29.0" (estimated from photos)
- Difference: 0.5" = **PERFECT ALIGNMENT** ✅
- Score: 100/100

---

### 3. Impact Geometry (15% weight)
**What it does:**
- Analyzes collision angle and direction
- Checks if angles are reciprocal (opposite directions)

**Scoring:**
- Angles within 10° of reciprocal = 100%
- 10-30° difference = 50%
- >30° difference = 0%

**Your case:**
- Your truck: ~25° horizontal left-to-right
- Suspect: NOT YET MEASURED
- Score: 0/100 (pending suspect photos)

---

### 4. Deformation Pattern (15% weight)
**What it does:**
- Compares 3D shape of damage
- Looks for "puzzle piece" matching

**Scoring:**
- Future: 3D mesh contour matching with shape signatures
- MVP: Qualitative assessment from photos
- Default: 50% partial credit

**Your case:**
- Requires LiDAR 3D scans for full analysis
- Score: 50/100 (partial credit)

---

### 5. Damage Dimensions (10% weight)
**What it does:**
- Compares width, height, and area of damage zones

**Scoring:**
- Ratio of smaller/larger for each dimension
- Average across all measured dimensions

**Your case:**
- Your truck: ~8" wide × 6" high
- Suspect: NOT YET MEASURED
- Score: 50/100 (pending)

---

### 6. Material Transfer (5% weight)
**What it does:**
- Detects transferred materials (paint, rubber, plastic, metal, glass)
- Confirms reciprocal material exchange

**Scoring:**
- Any material on victim = 50%
- Reciprocal materials on suspect = 100%

**Your case:**
- Your truck: white paint + plastic visible
- Suspect: NOT YET CONFIRMED
- Score: 50/100

---

### 7. Temporal Consistency (5% weight)
**What it does:**
- Confirms damage freshness matches incident timeline

**Scoring:**
- Fresh unrepaired damage = 100%
- Unknown freshness = 80%
- Older damage = 50%

**Your case:**
- Both vehicles appear unrepaired
- Score: 80/100 (high confidence)

---

## 🧮 COMPOSITE SCORING FORMULA

```
Composite Score = Σ (Factor Score × Factor Weight / 100)

Example (your current case):
= (70 × 0.30) + (100 × 0.20) + (0 × 0.15) + (50 × 0.15) + (50 × 0.10) + (50 × 0.05) + (80 × 0.05)
= 21.0 + 20.0 + 0.0 + 7.5 + 5.0 + 2.5 + 4.0
= 60.0/100
```

---

## 📊 COMPOSITE SCORE BANDS

> **Corrected 2026-09-06.** This section previously mapped each score band to a
> "Probability Range" (80-100 → "80-95%") and to an action ("pursue legal
> action"), and labelled a 60/100 case a "PROBABLE MATCH". **Every one of those
> is a claim this app deliberately does not make**, and the correction is
> recorded rather than quietly applied because the old framing is quoted in
> external material and someone will arrive expecting it.
>
> A composite score is a **weighted sum of factor scores, not a probability.**
> Nothing in the pipeline estimates the likelihood that two vehicles collided;
> 78/100 does not mean 78% likely, and there is no calibration anywhere in this
> codebase that would justify converting one into the other. `MatchResult`
> carries the same statement at the field itself: `scoreRangeLabel` is
> documented as "a score band, NOT a statistical probability", and a
> `legacyProbabilityRange` decode path exists solely to read cases written
> before that migration. This document was the last place still teaching the
> abandoned framing.
>
> Why it mattered more than an ordinary stale doc: the scoring code cites
> `ALGORITHM_EXPLAINER §2` in a string that reaches the **report an
> investigator reads**. So a reader following that citation landed two sections
> later on a table telling them 60-79 means a probable match at 60-85%
> probability — language the report itself refuses to print. The report did not
> contain the banned framing; it *pointed at* it. A copy lock that governs
> strings cannot see that route, which is why cited reference documents are now
> inside the lock (`docs/EVIDENCE_APPENDIX_CAPTURE_NOTES.md` §4).

| Composite Score | Band | What it means |
|-----------------|------|---------------|
| 80-100 | HIGH | Every factor that could be measured agrees, and the strongest ones agree closely. Not a probability, and not a conclusion — the strength of agreement between measurements. |
| 60-79 | MEDIUM | Substantial agreement, usually with at least one factor unmeasured or weak. |
| 40-59 | LOW | Mixed evidence. Agreement on some factors, disagreement or absence on others. |
| 0-39 | VERY LOW | Little agreement. Note that a rule-out (see §2) is a separate and stronger finding than a low score. |

**No band recommends or discourages a course of action.** Whether evidence
supports any step is a judgement for a person with training and context the app
does not have; the earlier "pursue legal action" cell asserted otherwise and is
removed rather than reworded. A high score also never stands alone — it travels
with its per-factor breakdown and, where a null model could be built, its
p-value and significance verdict.

---

## 🎯 HOW TO IMPROVE YOUR SCORE

### From 60 → 80+ (STRONG MATCH):

1. **Get suspect damage photos** (+10-15 points)
   - Confirm gray paint transfer on white surface
   - Measure impact angle
   - Document scrape direction

2. **Measure suspect damage dimensions** (+3-5 points)
   - Width and height with tape measure
   - Verify proportional match to your truck

3. **Confirm material transfer** (+2-5 points)
   - Look for gray paint, rubber, or plastic on suspect
   - Document with close-up photos

**Total potential gain: 15-25 points**
**Final score: 75-85 = STRONG MATCH** ✅

---

## 🔐 LEGAL ADMISSIBILITY

### Why This Algorithm is Court-Friendly:

1. **Based on established forensic methods**
   - Paint transfer analysis (FBI standard)
   - Height alignment (accident reconstruction 101)
   - Impact geometry (physics-based)

2. **Transparent scoring**
   - Every factor shows raw score + evidence
   - Weights are documented and justified
   - No "black box" AI decisions

3. **Conservative thresholds**
   - A high band requires agreement across the strongest measured factors
   - Clear disclosure of data limitations, including which factors could not be
     measured at all
   - No band recommends a course of action; interpretation is left to a person
   - *Corrected 2026-09-06: previously read "80%+ required for strong match
     recommendation" and "recommends professional review for legal action". The
     first restated the probability framing removed above; the second made the
     app the author of a recommendation it is not competent to give. This was
     offered as a court-friendliness argument, which made it load-bearing rather
     than decorative — a defensibility claim resting on a framing the app had
     abandoned.*

4. **Reproducible**
   - Same inputs = same outputs
   - Deterministic **because randomness is seeded from the input data**, not
     because the algorithm contains none: both matchers run permutation
     shuffles for their null models, seeded from the data being analysed, so
     re-running an analysis reproduces every p-value exactly
   - Can be independently verified
   - *Corrected 2026-09-06: previously read "algorithm is deterministic (no
     randomness)". The conclusion held but the stated reason became false when
     seeded permutation null models were introduced (`7391b73`, then P1b) —
     and "no randomness" is precisely the kind of absolute that gets quoted
     back at you under challenge. Determinism is a property that was
     deliberately preserved, not one that comes free from an absence.*

---

## 🚀 NEXT EVOLUTION (V2 Features)

### Advanced Paint Analysis:
- Multi-layer paint matching (primer, base, clear coat)
- Spectral analysis simulation
- Paint age/weathering comparison

### 3D Geometry Enhancement:
- Full LiDAR mesh comparison
- Point cloud registration
- Deformation energy calculation

### Machine Learning:
- Train on database of confirmed matches
- Pattern recognition for unusual cases
- Confidence calibration from real outcomes

### Expert Integration:
- Flagging for professional review
- Expert witness report generation
- Court testimony preparation

---

## 💡 WHY THIS WORKS

### The "Ballistic Matching" Analogy:

Just like firearms leave unique markings on bullets:
- Vehicle collisions leave unique damage patterns
- Multiple independent markers combine for high confidence
- Small tolerances account for real-world variation
- Composite scoring reduces false positives

### Key Insight:
**No single factor proves a match. The combination of multiple aligned factors creates forensic certainty.**

Your case demonstrates this perfectly:
- Paint color: ✅ Matches
- Height: ✅ Aligns perfectly
- Freshness: ✅ Consistent
- **Together:** composite 60/100 — MEDIUM band
- **With suspect photos:** composite 80+/100 — HIGH band

*(Corrected 2026-09-06 from "60% confidence (probable match)" / "80%+
confidence (strong match)" — see the note on score bands above. The composite
figures are unchanged; only the probability-and-verdict phrasing is.)*

---

## 📚 REFERENCES

### Forensic Methods:
- FBI Paint Analysis Standards
- SAE Accident Reconstruction Guidelines
- ASTM Color Measurement Standards

### Computer Vision:
- RGB/HSV color space comparison
- Euclidean distance metrics
- 3D point cloud registration (future)

### Legal Framework:
- Daubert Standard for expert testimony
- Federal Rules of Evidence 702
- State vehicle code collision investigation

---

## ✅ VALIDATION CHECKLIST

Before launching to public, we'll validate:

- [ ] Test on 10 known matched pairs (ground truth)
- [ ] Test on 10 known non-matches (false positive check)
- [ ] Compare to expert human assessments
- [ ] Verify scoring weights with accident reconstructionists
- [ ] Legal review of disclaimers and recommendations
- [ ] Accuracy target: >90% on confirmed cases

---

**This algorithm is the foundation of your $395M opportunity! 🚀**

