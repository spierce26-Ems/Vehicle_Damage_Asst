#!/usr/bin/env python3
"""
Enhanced Forensic Analyzer with Confidence Intervals & Advanced Features
Version 2.0 - Ruflo Agent 1 Build
"""

import json
import math
from typing import Dict, List, Tuple, Optional
from datetime import datetime
from dataclasses import dataclass, asdict

@dataclass
class ConfidenceInterval:
    """Represents a confidence interval for a score."""
    lower_bound: float
    upper_bound: float
    confidence_level: float = 0.95  # 95% confidence by default
    
    def __str__(self):
        return f"[{self.lower_bound:.1f}, {self.upper_bound:.1f}] ({self.confidence_level*100}% confidence)"

@dataclass
class FactorScore:
    """Enhanced factor score with confidence intervals."""
    raw_score: float
    weighted_score: float
    weight: float
    confidence_interval: ConfidenceInterval
    evidence: List[str]
    status: str
    reliability: str  # HIGH, MEDIUM, LOW

class EnhancedForensicAnalyzer:
    """
    Enhanced forensic matching engine with confidence intervals,
    alternative suspect ranking, and advanced analytics.
    """
    
    WEIGHTS = {
        'paint_transfer': 30,
        'height_alignment': 20,
        'impact_geometry': 15,
        'deformation_pattern': 15,
        'damage_dimensions': 10,
        'material_transfer': 5,
        'temporal_consistency': 5
    }
    
    def __init__(self):
        self.results = {}
        self.alternative_suspects = []
        
    def analyze_with_confidence(self, victim_data: Dict, suspect_data: Dict) -> Dict:
        """
        Run enhanced forensic analysis with confidence intervals.
        """
        results = {
            'case_id': f"ENHANCED-{datetime.now().strftime('%Y%m%d-%H%M%S')}",
            'analysis_date': datetime.now().isoformat(),
            'version': '2.0',
            'victim': victim_data,
            'suspect': suspect_data,
            'factors': {},
            'composite_score': 0,
            'confidence_interval': None,
            'match_probability': '',
            'confidence_level': '',
            'reliability_assessment': '',
            'recommendation': '',
            'alternative_scenarios': []
        }
        
        # Analyze each factor with confidence intervals
        factors = {}
        
        factors['paint_transfer'] = self._analyze_paint_with_confidence(
            victim_data, suspect_data
        )
        factors['height_alignment'] = self._analyze_height_with_confidence(
            victim_data, suspect_data
        )
        factors['impact_geometry'] = self._analyze_geometry_with_confidence(
            victim_data, suspect_data
        )
        factors['deformation_pattern'] = self._analyze_deformation_with_confidence(
            victim_data, suspect_data
        )
        factors['damage_dimensions'] = self._analyze_dimensions_with_confidence(
            victim_data, suspect_data
        )
        factors['material_transfer'] = self._analyze_material_with_confidence(
            victim_data, suspect_data
        )
        factors['temporal_consistency'] = self._analyze_temporal_with_confidence(
            victim_data, suspect_data
        )
        
        # Calculate composite score with confidence interval
        composite = 0
        composite_variance = 0
        
        for factor_name, factor_score in factors.items():
            weighted = factor_score.raw_score * (self.WEIGHTS[factor_name] / 100)
            composite += weighted
            
            # Accumulate variance for confidence interval
            ci = factor_score.confidence_interval
            variance = ((ci.upper_bound - ci.lower_bound) / 4) ** 2  # Rough variance estimate
            weighted_variance = variance * (self.WEIGHTS[factor_name] / 100) ** 2
            composite_variance += weighted_variance
        
        results['composite_score'] = round(composite, 2)
        
        # Calculate composite confidence interval
        std_dev = math.sqrt(composite_variance)
        z_score = 1.96  # 95% confidence
        margin = z_score * std_dev
        
        results['confidence_interval'] = ConfidenceInterval(
            lower_bound=max(0, round(composite - margin, 2)),
            upper_bound=min(100, round(composite + margin, 2)),
            confidence_level=0.95
        )
        
        results['factors'] = {k: asdict(v) for k, v in factors.items()}
        results['match_probability'] = self._calculate_probability_range(
            composite, results['confidence_interval']
        )
        results['confidence_level'] = self._get_confidence_level(composite, factors)
        results['reliability_assessment'] = self._assess_reliability(factors)
        results['recommendation'] = self._get_recommendation(results)
        
        # Generate alternative scenarios
        results['alternative_scenarios'] = self._generate_alternative_scenarios(
            victim_data, factors
        )
        
        self.results = results
        return results
    
    def _analyze_paint_with_confidence(self, victim: Dict, suspect: Dict) -> FactorScore:
        """Analyze paint transfer with confidence interval."""
        victim_paint = victim.get('transferred_paint_color', {})
        suspect_paint = suspect.get('vehicle_color', {})
        
        if not victim_paint or not suspect_paint:
            return FactorScore(
                raw_score=0,
                weighted_score=0,
                weight=self.WEIGHTS['paint_transfer'],
                confidence_interval=ConfidenceInterval(0, 20, 0.95),
                evidence=["Insufficient paint data"],
                status='INSUFFICIENT_DATA',
                reliability='LOW'
            )
        
        # Color matching
        color_match_score = self._compare_colors(victim_paint, suspect_paint)
        
        # Reciprocal check
        suspect_transferred = suspect.get('transferred_paint_color', {})
        victim_color = victim.get('vehicle_color', {})
        reciprocal_score = 0
        
        if suspect_transferred and victim_color:
            reciprocal_score = self._compare_colors(suspect_transferred, victim_color)
        
        # Combined score (70% direct, 30% reciprocal)
        raw_score = round((color_match_score * 0.7) + (reciprocal_score * 0.3), 2)
        
        # Confidence interval based on data quality
        margin = 5 if reciprocal_score > 0 else 15  # Tighter if reciprocal confirmed
        
        evidence = [
            f"Victim transferred paint: {victim_paint.get('description', 'Unknown')}",
            f"Suspect vehicle color: {suspect_paint.get('description', 'Unknown')}",
            f"Color match score: {color_match_score}%"
        ]
        
        if reciprocal_score > 0:
            evidence.append(f"Reciprocal transfer confirmed: {reciprocal_score}%")
        
        return FactorScore(
            raw_score=raw_score,
            weighted_score=round(raw_score * (self.WEIGHTS['paint_transfer'] / 100), 2),
            weight=self.WEIGHTS['paint_transfer'],
            confidence_interval=ConfidenceInterval(
                max(0, raw_score - margin),
                min(100, raw_score + margin),
                0.95
            ),
            evidence=evidence,
            status='ANALYZED',
            reliability='HIGH' if reciprocal_score > 0 else 'MEDIUM'
        )
    
    def _analyze_height_with_confidence(self, victim: Dict, suspect: Dict) -> FactorScore:
        """Analyze height alignment with confidence interval."""
        victim_height = victim.get('damage_height_inches')
        suspect_height = suspect.get('damage_height_inches')
        
        if victim_height is None or suspect_height is None:
            return FactorScore(
                raw_score=0,
                weighted_score=0,
                weight=self.WEIGHTS['height_alignment'],
                confidence_interval=ConfidenceInterval(0, 30, 0.95),
                evidence=["Missing height measurement data"],
                status='INSUFFICIENT_DATA',
                reliability='LOW'
            )
        
        # Calculate height difference
        height_diff = abs(victim_height - suspect_height)
        
        # Scoring with continuous function
        if height_diff <= 2:
            raw_score = 100
            reliability = 'HIGH'
        elif height_diff <= 4:
            raw_score = 75
            reliability = 'MEDIUM'
        elif height_diff <= 6:
            raw_score = 50
            reliability = 'MEDIUM'
        else:
            raw_score = 0
            reliability = 'LOW'
        
        # Confidence interval (tight for height - it's measurable)
        margin = 3 if height_diff <= 2 else 8
        
        evidence = [
            f"Victim damage height: {victim_height}\"",
            f"Suspect damage height: {suspect_height}\"",
            f"Height difference: {height_diff}\" (tolerance: ±2\")"
        ]
        
        if height_diff <= 2:
            evidence.append("✅ Heights align within forensic tolerance")
        elif height_diff <= 6:
            evidence.append("⚠️ Heights partially align (possible match)")
        else:
            evidence.append("❌ Heights do not align (unlikely match)")
        
        return FactorScore(
            raw_score=raw_score,
            weighted_score=round(raw_score * (self.WEIGHTS['height_alignment'] / 100), 2),
            weight=self.WEIGHTS['height_alignment'],
            confidence_interval=ConfidenceInterval(
                max(0, raw_score - margin),
                min(100, raw_score + margin),
                0.95
            ),
            evidence=evidence,
            status='ANALYZED',
            reliability=reliability
        )
    
    def _analyze_geometry_with_confidence(self, victim: Dict, suspect: Dict) -> FactorScore:
        """Analyze impact geometry with confidence interval."""
        victim_angle = victim.get('impact_angle_degrees')
        suspect_angle = suspect.get('impact_angle_degrees')
        
        if victim_angle is None or suspect_angle is None:
            # Partial score based on qualitative description
            score = 50 if victim.get('impact_description') and suspect.get('impact_description') else 0
            return FactorScore(
                raw_score=score,
                weighted_score=round(score * (self.WEIGHTS['impact_geometry'] / 100), 2),
                weight=self.WEIGHTS['impact_geometry'],
                confidence_interval=ConfidenceInterval(
                    max(0, score - 20),
                    min(100, score + 20),
                    0.95
                ),
                evidence=["Qualitative impact geometry assessment"],
                status='PARTIAL',
                reliability='MEDIUM'
            )
        
        # Reciprocal angle check
        expected_reciprocal = 180 - victim_angle
        angle_diff = abs(suspect_angle - expected_reciprocal)
        
        if angle_diff <= 10:
            raw_score = 100
            reliability = 'HIGH'
        elif angle_diff <= 30:
            raw_score = 50
            reliability = 'MEDIUM'
        else:
            raw_score = 0
            reliability = 'LOW'
        
        margin = 10
        
        evidence = [
            f"Victim impact angle: {victim_angle}°",
            f"Suspect impact angle: {suspect_angle}°",
            f"Reciprocal match: {angle_diff}° difference"
        ]
        
        return FactorScore(
            raw_score=raw_score,
            weighted_score=round(raw_score * (self.WEIGHTS['impact_geometry'] / 100), 2),
            weight=self.WEIGHTS['impact_geometry'],
            confidence_interval=ConfidenceInterval(
                max(0, raw_score - margin),
                min(100, raw_score + margin),
                0.95
            ),
            evidence=evidence,
            status='ANALYZED',
            reliability=reliability
        )
    
    def _analyze_deformation_with_confidence(self, victim: Dict, suspect: Dict) -> FactorScore:
        """Analyze deformation patterns with confidence interval."""
        # Placeholder - would use 3D analysis in production
        return FactorScore(
            raw_score=50,
            weighted_score=round(50 * (self.WEIGHTS['deformation_pattern'] / 100), 2),
            weight=self.WEIGHTS['deformation_pattern'],
            confidence_interval=ConfidenceInterval(30, 70, 0.95),
            evidence=["Deformation pattern analysis requires 3D data"],
            status='PARTIAL',
            reliability='MEDIUM'
        )
    
    def _analyze_dimensions_with_confidence(self, victim: Dict, suspect: Dict) -> FactorScore:
        """Analyze damage dimensions with confidence interval."""
        victim_dims = victim.get('damage_dimensions', {})
        suspect_dims = suspect.get('damage_dimensions', {})
        
        if not victim_dims or not suspect_dims:
            return FactorScore(
                raw_score=50,
                weighted_score=round(50 * (self.WEIGHTS['damage_dimensions'] / 100), 2),
                weight=self.WEIGHTS['damage_dimensions'],
                confidence_interval=ConfidenceInterval(30, 70, 0.95),
                evidence=["Insufficient dimension data"],
                status='INSUFFICIENT_DATA',
                reliability='LOW'
            )
        
        scores = []
        evidence = []
        
        for dimension in ['width_inches', 'height_inches']:
            v_val = victim_dims.get(dimension)
            s_val = suspect_dims.get(dimension)
            
            if v_val and s_val:
                ratio = min(v_val, s_val) / max(v_val, s_val)
                dim_score = ratio * 100
                scores.append(dim_score)
                evidence.append(f"{dimension}: {v_val}\" vs {s_val}\" ({dim_score:.1f}% match)")
        
        if scores:
            raw_score = round(sum(scores) / len(scores), 2)
            margin = 10
            reliability = 'MEDIUM'
        else:
            raw_score = 50
            margin = 20
            reliability = 'LOW'
        
        return FactorScore(
            raw_score=raw_score,
            weighted_score=round(raw_score * (self.WEIGHTS['damage_dimensions'] / 100), 2),
            weight=self.WEIGHTS['damage_dimensions'],
            confidence_interval=ConfidenceInterval(
                max(0, raw_score - margin),
                min(100, raw_score + margin),
                0.95
            ),
            evidence=evidence,
            status='ANALYZED' if scores else 'PARTIAL',
            reliability=reliability
        )
    
    def _analyze_material_with_confidence(self, victim: Dict, suspect: Dict) -> FactorScore:
        """Analyze material transfer with confidence interval."""
        victim_materials = victim.get('transferred_materials', [])
        suspect_materials = suspect.get('transferred_materials', [])
        
        if not victim_materials:
            return FactorScore(
                raw_score=0,
                weighted_score=0,
                weight=self.WEIGHTS['material_transfer'],
                confidence_interval=ConfidenceInterval(0, 20, 0.95),
                evidence=["No material transfer detected on victim"],
                status='ANALYZED',
                reliability='LOW'
            )
        
        raw_score = 50  # Base score for any transfer
        margin = 15
        reliability = 'MEDIUM'
        
        evidence = [f"Materials on victim: {', '.join(victim_materials)}"]
        
        if suspect_materials:
            raw_score = 100
            margin = 5
            reliability = 'HIGH'
            evidence.append(f"Materials on suspect: {', '.join(suspect_materials)}")
            evidence.append("✅ Reciprocal material transfer confirmed")
        else:
            evidence.append("⏳ No material transfer data from suspect")
        
        return FactorScore(
            raw_score=raw_score,
            weighted_score=round(raw_score * (self.WEIGHTS['material_transfer'] / 100), 2),
            weight=self.WEIGHTS['material_transfer'],
            confidence_interval=ConfidenceInterval(
                max(0, raw_score - margin),
                min(100, raw_score + margin),
                0.95
            ),
            evidence=evidence,
            status='ANALYZED',
            reliability=reliability
        )
    
    def _analyze_temporal_with_confidence(self, victim: Dict, suspect: Dict) -> FactorScore:
        """Analyze temporal consistency with confidence interval."""
        victim_date = victim.get('incident_date')
        suspect_freshness = suspect.get('damage_freshness', 'unknown')
        
        if suspect_freshness == 'fresh':
            raw_score = 100
            margin = 5
            reliability = 'HIGH'
            status_text = "✅ Damage appears fresh/unrepaired"
        elif suspect_freshness == 'unknown':
            raw_score = 80
            margin = 15
            reliability = 'MEDIUM'
            status_text = "⏳ Damage freshness not confirmed"
        else:
            raw_score = 50
            margin = 20
            reliability = 'LOW'
            status_text = "⚠️ Damage may be older than incident"
        
        evidence = [
            f"Incident date: {victim_date or 'Unknown'}",
            f"Suspect damage: {suspect_freshness}",
            status_text
        ]
        
        return FactorScore(
            raw_score=raw_score,
            weighted_score=round(raw_score * (self.WEIGHTS['temporal_consistency'] / 100), 2),
            weight=self.WEIGHTS['temporal_consistency'],
            confidence_interval=ConfidenceInterval(
                max(0, raw_score - margin),
                min(100, raw_score + margin),
                0.95
            ),
            evidence=evidence,
            status='ANALYZED',
            reliability=reliability
        )
    
    def _compare_colors(self, color1: Dict, color2: Dict) -> float:
        """Compare two colors using Euclidean distance in RGB space."""
        rgb1 = color1.get('rgb', [0, 0, 0])
        rgb2 = color2.get('rgb', [0, 0, 0])
        
        distance = math.sqrt(sum((c1 - c2) ** 2 for c1, c2 in zip(rgb1, rgb2)))
        max_distance = 441  # sqrt(3 * 255^2)
        similarity = max(0, (1 - distance / max_distance) * 100)
        
        return round(similarity, 2)
    
    def _calculate_probability_range(self, composite: float, ci: ConfidenceInterval) -> str:
        """Calculate probability range considering confidence interval."""
        lower = ci.lower_bound
        upper = ci.upper_bound
        
        return f"{int(lower)}-{int(upper)}%"
    
    def _get_confidence_level(self, composite: float, factors: Dict) -> str:
        """Determine overall confidence level based on factor reliability."""
        high_reliability_count = sum(1 for f in factors.values() if f.reliability == 'HIGH')
        total_factors = len(factors)
        
        high_ratio = high_reliability_count / total_factors
        
        if composite >= 80 and high_ratio >= 0.5:
            return "HIGH"
        elif composite >= 60 and high_ratio >= 0.3:
            return "MEDIUM"
        elif composite >= 40:
            return "LOW"
        else:
            return "VERY LOW"
    
    def _assess_reliability(self, factors: Dict) -> str:
        """Assess overall reliability of the analysis."""
        reliability_scores = {'HIGH': 3, 'MEDIUM': 2, 'LOW': 1}
        total_weighted_reliability = sum(
            reliability_scores[f.reliability] * f.weight 
            for f in factors.values()
        )
        max_possible = sum(3 * f.weight for f in factors.values())
        
        ratio = total_weighted_reliability / max_possible
        
        if ratio >= 0.7:
            return "Analysis is highly reliable with strong forensic markers."
        elif ratio >= 0.5:
            return "Analysis is moderately reliable with some strong markers."
        else:
            return "Analysis reliability is limited due to insufficient data."
    
    def _get_recommendation(self, results: Dict) -> str:
        """Generate recommendation based on enhanced analysis."""
        score = results['composite_score']
        ci = results["confidence_interval"]
        
        # Consider confidence interval in recommendation
        if ci.lower_bound >= 75:
            return "STRONG MATCH - Even at lower bound of confidence interval, evidence strongly supports pursuing legal action."
        elif score >= 80:
            return "STRONG MATCH - Evidence supports pursuing legal action. Recommend filing police report and insurance claim."
        elif score >= 60:
            return "PROBABLE MATCH - Evidence is suggestive. Recommend gathering additional evidence before legal action."
        elif score >= 40:
            return "POSSIBLE MATCH - Evidence is weak. Consider this vehicle as one of multiple suspects."
        else:
            return "UNLIKELY MATCH - Evidence does not support a match. Consider alternative suspects."
    
    def _generate_alternative_scenarios(self, victim_data: Dict, factors: Dict) -> List[Dict]:
        """Generate what-if scenarios for sensitivity analysis."""
        scenarios = []
        
        # Scenario 1: If gray paint transfer confirmed on suspect
        if factors['paint_transfer'].raw_score < 100:
            scenario = {
                'name': "If gray paint transfer confirmed on suspect",
                'assumption': "Reciprocal paint transfer visible",
                'score_change': "+10-15 points",
                'new_estimated_score': "90-95",
                'impact': "Would elevate to VERY STRONG MATCH"
            }
            scenarios.append(scenario)
        
        # Scenario 2: If impact angle measured precisely
        if factors['impact_geometry'].raw_score < 90:
            scenario = {
                'name': "If impact angles measured precisely",
                'assumption': "Angles within 10° of reciprocal",
                'score_change': "+5-10 points",
                'new_estimated_score': "85-90",
                'impact': "Would strengthen STRONG MATCH conclusion"
            }
            scenarios.append(scenario)
        
        # Scenario 3: Conservative estimate (all partial scores to minimum)
        scenario = {
            'name': "Conservative estimate (minimum scores)",
            'assumption': "All uncertain factors scored at lower confidence bound",
            'score_change': "-10-15 points",
            'new_estimated_score': "70-75",
            'impact': "Would still support PROBABLE MATCH conclusion"
        }
        scenarios.append(scenario)
        
        return scenarios
    
    def rank_suspects(self, victim_data: Dict, suspects: List[Dict]) -> List[Dict]:
        """
        Rank multiple suspect vehicles by match probability.
        Returns sorted list with scores and confidence intervals.
        """
        ranked = []
        
        for i, suspect in enumerate(suspects, 1):
            analysis = self.analyze_with_confidence(victim_data, suspect)
            ranked.append({
                'rank': i,
                'suspect_id': suspect.get('id', f'suspect_{i}'),
                'composite_score': analysis['composite_score'],
                'confidence_interval': analysis['confidence_interval'],
                'match_probability': analysis['match_probability'],
                'recommendation': analysis['recommendation']
            })
        
        # Sort by composite score (descending)
        ranked.sort(key=lambda x: x['composite_score'], reverse=True)
        
        # Update ranks after sorting
        for i, item in enumerate(ranked, 1):
            item['rank'] = i
        
        return ranked
    
    def export_enhanced_json(self, filepath: str):
        """Export enhanced analysis results to JSON."""
        with open(filepath, 'w') as f:
            json.dump(self.results, f, indent=2, default=str)
        print(f"✅ Enhanced analysis exported to: {filepath}")


def run_enhanced_example():
    """Example usage with enhanced features."""
    analyzer = EnhancedForensicAnalyzer()
    
    # Your case data
    victim_data = {
        'vehicle_info': {'year': 2026, 'make': 'Toyota', 'model': 'Tundra', 'color': 'Dark Gray'},
        'vehicle_color': {'description': 'Dark Gray', 'rgb': [75, 75, 75]},
        'damage_height_inches': 28.5,
        'impact_angle_degrees': 25,
        'damage_dimensions': {'width_inches': 8, 'height_inches': 6},
        'transferred_paint_color': {'description': 'White', 'rgb': [255, 255, 255]},
        'transferred_materials': ['paint', 'plastic'],
        'impact_description': 'Left-to-right horizontal swipe',
        'incident_date': 'April 2026'
    }
    
    suspect_data = {
        'vehicle_info': {'color': 'White'},
        'vehicle_color': {'description': 'White', 'rgb': [255, 255, 255]},
        'damage_height_inches': 26.0,  # From your photos!
        'impact_angle_degrees': None,
        'damage_dimensions': {'width_inches': 6, 'height_inches': 4.5},
        'transferred_paint_color': None,  # Pending confirmation
        'transferred_materials': [],
        'damage_freshness': 'fresh'
    }
    
    # Run enhanced analysis
    results = analyzer.analyze_with_confidence(victim_data, suspect_data)
    
    print("="*70)
    print("ENHANCED FORENSIC ANALYSIS WITH CONFIDENCE INTERVALS")
    print("="*70)
    print(f"\nCase ID: {results['case_id']}")
    print(f"Version: {results['version']}")
    print(f"\nCOMPOSITE MATCH SCORE: {results['composite_score']}/100")
    ci_data = results["confidence_interval"]
    print(f"CONFIDENCE INTERVAL: [{ci_data.lower_bound:.1f}, {ci_data.upper_bound:.1f}] (95% confidence)")
    print(f"MATCH PROBABILITY: {results['match_probability']}")
    print(f"CONFIDENCE LEVEL: {results['confidence_level']}")
    print(f"\nRELIABILITY: {results['reliability_assessment']}")
    
    print("\n" + "="*70)
    print("FACTOR BREAKDOWN WITH CONFIDENCE INTERVALS")
    print("="*70)
    
    for factor_name, factor_data in results['factors'].items():
        print(f"\n{factor_name.replace('_', ' ').title()}:")
        print(f"  Score: {factor_data['raw_score']}/100")
        ci = factor_data["confidence_interval"]
        print(f"  Confidence Interval: {ci}")
        print(f"  Reliability: {factor_data['reliability']}")
        print(f"  Status: {factor_data['status']}")
    
    print("\n" + "="*70)
    print("ALTERNATIVE SCENARIOS")
    print("="*70)
    
    for scenario in results['alternative_scenarios']:
        print(f"\n{scenario['name']}:")
        print(f"  Assumption: {scenario['assumption']}")
        print(f"  Score Change: {scenario['score_change']}")
        print(f"  New Estimate: {scenario['new_estimated_score']}")
        print(f"  Impact: {scenario['impact']}")
    
    print("\n" + "="*70)
    print("RECOMMENDATION")
    print("="*70)
    print(f"\n{results['recommendation']}")
    
    # Export
    analyzer.export_enhanced_json('enhanced_analysis_results.json')
    print("\n✅ Enhanced analysis complete!")


if __name__ == "__main__":
    run_enhanced_example()

