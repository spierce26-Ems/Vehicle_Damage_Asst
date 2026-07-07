#!/usr/bin/env python3
"""
Vehicle Damage Forensic Matching System - Core Algorithm
Author: AI Forensic Analysis Engine
Version: 1.0.0 MVP
"""

import os
import json
from datetime import datetime
from typing import Dict, List, Tuple, Optional
import math

class ForensicAnalyzer:
    """
    Core forensic matching engine for vehicle damage analysis.
    Implements 7-factor scoring system with weighted composite.
    """
    
    # Scoring weights (must sum to 100)
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
        """Initialize the forensic analyzer."""
        self.case_data = {}
        self.analysis_results = {}
        
    def analyze_case(self, victim_data: Dict, suspect_data: Dict) -> Dict:
        """
        Run complete 7-factor forensic analysis.
        
        Args:
            victim_data: Dict containing victim vehicle information
            suspect_data: Dict containing suspect vehicle information
            
        Returns:
            Dict with complete analysis results and match probability
        """
        results = {
            'case_id': f"CASE-{datetime.now().strftime('%Y%m%d-%H%M%S')}",
            'analysis_date': datetime.now().isoformat(),
            'victim': victim_data,
            'suspect': suspect_data,
            'factors': {},
            'composite_score': 0,
            'match_probability': 0,
            'confidence_level': '',
            'recommendation': ''
        }
        
        # Run each forensic factor analysis
        results['factors']['paint_transfer'] = self._analyze_paint_transfer(
            victim_data, suspect_data
        )
        results['factors']['height_alignment'] = self._analyze_height_alignment(
            victim_data, suspect_data
        )
        results['factors']['impact_geometry'] = self._analyze_impact_geometry(
            victim_data, suspect_data
        )
        results['factors']['deformation_pattern'] = self._analyze_deformation(
            victim_data, suspect_data
        )
        results['factors']['damage_dimensions'] = self._analyze_dimensions(
            victim_data, suspect_data
        )
        results['factors']['material_transfer'] = self._analyze_material_transfer(
            victim_data, suspect_data
        )
        results['factors']['temporal_consistency'] = self._analyze_temporal(
            victim_data, suspect_data
        )
        
        # Calculate composite score
        composite = 0
        for factor, score_data in results['factors'].items():
            weighted_score = score_data['score'] * (self.WEIGHTS[factor] / 100)
            composite += weighted_score
            
        results['composite_score'] = round(composite, 2)
        results['match_probability'] = self._calculate_probability(composite)
        results['confidence_level'] = self._get_confidence_level(composite)
        results['recommendation'] = self._get_recommendation(results)
        
        self.analysis_results = results
        return results
    
    def _analyze_paint_transfer(self, victim: Dict, suspect: Dict) -> Dict:
        """
        Analyze paint transfer between vehicles.
        30% weight - highest importance.
        """
        result = {
            'score': 0,
            'max_score': 100,
            'weight': self.WEIGHTS['paint_transfer'],
            'evidence': [],
            'status': 'PENDING'
        }
        
        # Extract paint colors
        victim_paint = victim.get('transferred_paint_color', {})
        suspect_paint = suspect.get('vehicle_color', {})
        
        if not victim_paint or not suspect_paint:
            result['status'] = 'INSUFFICIENT_DATA'
            result['evidence'].append("Missing paint color data")
            return result
        
        # Color matching algorithm
        color_match_score = self._compare_colors(
            victim_paint, 
            suspect_paint
        )
        
        # Check for reciprocal transfer
        suspect_transferred = suspect.get('transferred_paint_color', {})
        victim_color = victim.get('vehicle_color', {})
        
        reciprocal_score = 0
        if suspect_transferred and victim_color:
            reciprocal_score = self._compare_colors(
                suspect_transferred,
                victim_color
            )
            result['evidence'].append(f"Reciprocal paint transfer detected: {reciprocal_score}% match")
        
        # Combine scores (direct match 70%, reciprocal 30%)
        result['score'] = round(
            (color_match_score * 0.7) + (reciprocal_score * 0.3),
            2
        )
        
        result['evidence'].append(
            f"Victim transferred paint: {victim_paint.get('description', 'Unknown')}"
        )
        result['evidence'].append(
            f"Suspect vehicle color: {suspect_paint.get('description', 'Unknown')}"
        )
        result['evidence'].append(
            f"Color match score: {color_match_score}%"
        )
        
        result['status'] = 'ANALYZED'
        return result
    
    def _analyze_height_alignment(self, victim: Dict, suspect: Dict) -> Dict:
        """
        Analyze bumper height alignment.
        20% weight - critical forensic marker.
        """
        result = {
            'score': 0,
            'max_score': 100,
            'weight': self.WEIGHTS['height_alignment'],
            'evidence': [],
            'status': 'PENDING'
        }
        
        victim_height = victim.get('damage_height_inches')
        suspect_height = suspect.get('damage_height_inches')
        
        if victim_height is None or suspect_height is None:
            result['status'] = 'INSUFFICIENT_DATA'
            result['evidence'].append("Missing height measurement data")
            return result
        
        # Calculate height difference
        height_diff = abs(victim_height - suspect_height)
        
        # Scoring formula:
        # 0-2 inches difference = 100%
        # 2-4 inches = 75%
        # 4-6 inches = 50%
        # >6 inches = 0%
        
        if height_diff <= 2:
            result['score'] = 100
        elif height_diff <= 4:
            result['score'] = 75
        elif height_diff <= 6:
            result['score'] = 50
        else:
            result['score'] = 0
            
        result['evidence'].append(f"Victim damage height: {victim_height}\"")
        result['evidence'].append(f"Suspect damage height: {suspect_height}\"")
        result['evidence'].append(f"Height difference: {height_diff}\" (tolerance: ±2\")")
        
        if height_diff <= 2:
            result['evidence'].append("✅ Heights align within forensic tolerance")
        elif height_diff <= 6:
            result['evidence'].append("⚠️ Heights partially align (possible match)")
        else:
            result['evidence'].append("❌ Heights do not align (unlikely match)")
            
        result['status'] = 'ANALYZED'
        return result
    
    def _analyze_impact_geometry(self, victim: Dict, suspect: Dict) -> Dict:
        """
        Analyze impact angle and geometry.
        15% weight.
        """
        result = {
            'score': 0,
            'max_score': 100,
            'weight': self.WEIGHTS['impact_geometry'],
            'evidence': [],
            'status': 'PENDING'
        }
        
        victim_angle = victim.get('impact_angle_degrees')
        suspect_angle = suspect.get('impact_angle_degrees')
        
        if victim_angle is None or suspect_angle is None:
            result['status'] = 'INSUFFICIENT_DATA'
            result['evidence'].append("Missing impact angle data")
            # Provide partial score based on description
            if victim.get('impact_description') and suspect.get('impact_description'):
                result['score'] = 50  # Partial credit for qualitative match
                result['evidence'].append("Using qualitative impact geometry assessment")
            return result
        
        # Angles should be reciprocal (opposite directions)
        # Victim left-to-right = Suspect right-to-left
        expected_reciprocal = 180 - victim_angle
        angle_diff = abs(suspect_angle - expected_reciprocal)
        
        # Scoring: Within 10° = 100%, 10-30° = 50%, >30° = 0%
        if angle_diff <= 10:
            result['score'] = 100
        elif angle_diff <= 30:
            result['score'] = 50
        else:
            result['score'] = 0
            
        result['evidence'].append(f"Victim impact angle: {victim_angle}°")
        result['evidence'].append(f"Suspect impact angle: {suspect_angle}°")
        result['evidence'].append(f"Reciprocal match: {angle_diff}° difference")
        
        result['status'] = 'ANALYZED'
        return result
    
    def _analyze_deformation(self, victim: Dict, suspect: Dict) -> Dict:
        """
        Analyze deformation patterns.
        15% weight.
        """
        result = {
            'score': 50,  # Default partial score
            'max_score': 100,
            'weight': self.WEIGHTS['deformation_pattern'],
            'evidence': ['Deformation pattern analysis requires 3D data'],
            'status': 'PARTIAL'
        }
        
        # Placeholder for future 3D mesh analysis
        # MVP uses qualitative assessment
        
        victim_pattern = victim.get('deformation_description', '')
        suspect_pattern = suspect.get('deformation_description', '')
        
        if victim_pattern and suspect_pattern:
            result['evidence'].append(f"Victim: {victim_pattern}")
            result['evidence'].append(f"Suspect: {suspect_pattern}")
            
        return result
    
    def _analyze_dimensions(self, victim: Dict, suspect: Dict) -> Dict:
        """
        Analyze damage dimensions (width, height, area).
        10% weight.
        """
        result = {
            'score': 0,
            'max_score': 100,
            'weight': self.WEIGHTS['damage_dimensions'],
            'evidence': [],
            'status': 'PENDING'
        }
        
        victim_dims = victim.get('damage_dimensions', {})
        suspect_dims = suspect.get('damage_dimensions', {})
        
        if not victim_dims or not suspect_dims:
            result['status'] = 'INSUFFICIENT_DATA'
            result['score'] = 50  # Partial credit
            return result
        
        # Compare width, height, and calculated area
        scores = []
        
        for dimension in ['width_inches', 'height_inches']:
            v_val = victim_dims.get(dimension)
            s_val = suspect_dims.get(dimension)
            
            if v_val and s_val:
                ratio = min(v_val, s_val) / max(v_val, s_val)
                dim_score = ratio * 100
                scores.append(dim_score)
                result['evidence'].append(
                    f"{dimension}: {v_val}\" vs {s_val}\" ({dim_score:.1f}% match)"
                )
        
        if scores:
            result['score'] = round(sum(scores) / len(scores), 2)
            result['status'] = 'ANALYZED'
        else:
            result['status'] = 'INSUFFICIENT_DATA'
            result['score'] = 50
            
        return result
    
    def _analyze_material_transfer(self, victim: Dict, suspect: Dict) -> Dict:
        """
        Analyze material transfer (paint, rubber, plastic, metal).
        5% weight.
        """
        result = {
            'score': 0,
            'max_score': 100,
            'weight': self.WEIGHTS['material_transfer'],
            'evidence': [],
            'status': 'ANALYZED'
        }
        
        victim_materials = victim.get('transferred_materials', [])
        suspect_materials = suspect.get('transferred_materials', [])
        
        if not victim_materials:
            result['score'] = 0
            result['evidence'].append("No material transfer detected on victim")
            return result
        
        # Score based on presence and reciprocity
        result['score'] = 50  # Base score for any transfer
        result['evidence'].append(f"Materials on victim: {', '.join(victim_materials)}")
        
        if suspect_materials:
            result['score'] = 100  # Full score for reciprocal transfer
            result['evidence'].append(f"Materials on suspect: {', '.join(suspect_materials)}")
            result['evidence'].append("✅ Reciprocal material transfer confirmed")
        else:
            result['evidence'].append("⏳ No material transfer data from suspect")
            
        return result
    
    def _analyze_temporal(self, victim: Dict, suspect: Dict) -> Dict:
        """
        Analyze temporal consistency (damage freshness).
        5% weight.
        """
        result = {
            'score': 80,  # Default high score for MVP
            'max_score': 100,
            'weight': self.WEIGHTS['temporal_consistency'],
            'evidence': [],
            'status': 'ANALYZED'
        }
        
        victim_date = victim.get('incident_date')
        suspect_freshness = suspect.get('damage_freshness', 'unknown')
        
        result['evidence'].append(f"Incident date: {victim_date or 'Unknown'}")
        result['evidence'].append(f"Suspect damage: {suspect_freshness}")
        
        if suspect_freshness == 'fresh':
            result['score'] = 100
            result['evidence'].append("✅ Damage appears fresh/unrepaired")
        elif suspect_freshness == 'unknown':
            result['score'] = 80
            result['evidence'].append("⏳ Damage freshness not confirmed")
        else:
            result['score'] = 50
            result['evidence'].append("⚠️ Damage may be older than incident")
            
        return result
    
    def _compare_colors(self, color1: Dict, color2: Dict) -> float:
        """
        Compare two colors and return similarity score (0-100).
        Uses RGB color space with Euclidean distance.
        """
        rgb1 = color1.get('rgb', [0, 0, 0])
        rgb2 = color2.get('rgb', [0, 0, 0])
        
        # Calculate Euclidean distance
        distance = math.sqrt(
            sum((c1 - c2) ** 2 for c1, c2 in zip(rgb1, rgb2))
        )
        
        # Max possible distance in RGB space is sqrt(3 * 255^2) ≈ 441
        # Convert to 0-100 scale (inverted so 0 distance = 100% match)
        max_distance = 441
        similarity = max(0, (1 - distance / max_distance) * 100)
        
        return round(similarity, 2)
    
    def _calculate_probability(self, composite_score: float) -> str:
        """Convert composite score to probability range."""
        if composite_score >= 80:
            return "80-95%"
        elif composite_score >= 70:
            return "70-85%"
        elif composite_score >= 60:
            return "60-75%"
        elif composite_score >= 50:
            return "50-65%"
        else:
            return "0-50%"
    
    def _get_confidence_level(self, composite_score: float) -> str:
        """Determine confidence level from composite score."""
        if composite_score >= 80:
            return "HIGH"
        elif composite_score >= 60:
            return "MEDIUM"
        elif composite_score >= 40:
            return "LOW"
        else:
            return "VERY LOW"
    
    def _get_recommendation(self, results: Dict) -> str:
        """Generate recommendation based on analysis."""
        score = results['composite_score']
        
        if score >= 80:
            return "STRONG MATCH - Evidence supports pursuing legal action. Recommend filing police report and insurance claim with this analysis."
        elif score >= 60:
            return "PROBABLE MATCH - Evidence is suggestive but not conclusive. Recommend gathering additional evidence (more photos, witness statements) before legal action."
        elif score >= 40:
            return "POSSIBLE MATCH - Evidence is weak. Consider this vehicle as one of multiple suspects. Additional investigation needed."
        else:
            return "UNLIKELY MATCH - Evidence does not support a match. Consider alternative suspects or re-examine available evidence."
    
    def export_json(self, filepath: str):
        """Export analysis results to JSON file."""
        with open(filepath, 'w') as f:
            json.dump(self.analysis_results, f, indent=2)
        print(f"✅ Analysis exported to: {filepath}")
    
    def generate_summary(self) -> str:
        """Generate human-readable summary of analysis."""
        if not self.analysis_results:
            return "No analysis results available."
        
        results = self.analysis_results
        
        summary = []
        summary.append("=" * 60)
        summary.append("FORENSIC MATCH ANALYSIS SUMMARY")
        summary.append("=" * 60)
        summary.append(f"\nCase ID: {results['case_id']}")
        summary.append(f"Analysis Date: {results['analysis_date']}")
        summary.append(f"\nCOMPOSITE MATCH SCORE: {results['composite_score']}/100")
        summary.append(f"MATCH PROBABILITY: {results['match_probability']}")
        summary.append(f"CONFIDENCE LEVEL: {results['confidence_level']}")
        summary.append("\n" + "-" * 60)
        summary.append("FACTOR BREAKDOWN:")
        summary.append("-" * 60)
        
        for factor, data in results['factors'].items():
            factor_name = factor.replace('_', ' ').title()
            score = data['score']
            weight = data['weight']
            weighted = round(score * (weight / 100), 2)
            
            summary.append(f"\n{factor_name} ({weight}% weight):")
            summary.append(f"  Raw Score: {score}/100")
            summary.append(f"  Weighted Contribution: {weighted} points")
            summary.append(f"  Status: {data['status']}")
            
            if data['evidence']:
                summary.append("  Evidence:")
                for evidence in data['evidence']:
                    summary.append(f"    • {evidence}")
        
        summary.append("\n" + "=" * 60)
        summary.append("RECOMMENDATION:")
        summary.append("=" * 60)
        summary.append(f"\n{results['recommendation']}")
        summary.append("\n" + "=" * 60)
        
        return "\n".join(summary)


# Example usage function
def run_example_analysis():
    """Run example analysis with sample data."""
    
    # Sample victim vehicle data (your Tundra)
    victim_data = {
        'vehicle_info': {
            'year': 2026,
            'make': 'Toyota',
            'model': 'Tundra',
            'color': 'Dark Gray/Charcoal'
        },
        'vehicle_color': {
            'description': 'Dark Gray',
            'rgb': [75, 75, 75]
        },
        'damage_height_inches': 28.5,  # Average of 27-30"
        'impact_angle_degrees': 25,  # Shallow horizontal
        'damage_dimensions': {
            'width_inches': 8,
            'height_inches': 6
        },
        'transferred_paint_color': {
            'description': 'White',
            'rgb': [255, 255, 255]
        },
        'transferred_materials': ['paint', 'plastic'],
        'impact_description': 'Left-to-right horizontal swipe',
        'deformation_description': 'Shallow scrape with paint transfer',
        'incident_date': 'April 2026'
    }
    
    # Sample suspect vehicle data
    suspect_data = {
        'vehicle_info': {
            'year': 'Unknown',
            'make': 'Unknown',
            'model': 'Sedan/Crossover',
            'color': 'White'
        },
        'vehicle_color': {
            'description': 'White',
            'rgb': [255, 255, 255]
        },
        'damage_height_inches': 29.0,  # Close to victim
        'impact_angle_degrees': None,  # Not measured yet
        'damage_dimensions': {
            'width_inches': None,
            'height_inches': None
        },
        'transferred_paint_color': None,  # Waiting for photos
        'transferred_materials': [],  # Waiting for photos
        'impact_description': None,
        'deformation_description': None,
        'damage_freshness': 'unknown'
    }
    
    # Run analysis
    analyzer = ForensicAnalyzer()
    results = analyzer.analyze_case(victim_data, suspect_data)
    
    # Print summary
    print(analyzer.generate_summary())
    
    # Export to JSON
    analyzer.export_json('analysis_results.json')
    
    return results


if __name__ == "__main__":
    print("🚨 FORENSIC ANALYZER - Starting Example Analysis\n")
    results = run_example_analysis()
    print("\n✅ Analysis complete!")
    print(f"\nNext steps: Add actual suspect vehicle photos to improve accuracy.")

