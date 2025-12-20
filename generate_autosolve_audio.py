"""
Generate auto-solve narration audio files
"""
import json
import os
import sys
from pathlib import Path

# Add Kokoro to path
KOKORO_PATH = r"D:\kokoro"
sys.path.insert(0, KOKORO_PATH)

from kokoro import KPipeline
import soundfile as sf

# Paths
ASSETS_PATH = r"Assets\audio_scripts"
OUTPUT_PATH = r"Assets\audio"

print("Initializing Kokoro TTS...")
pipeline = KPipeline(lang_code='a')
print("Kokoro TTS initialized!\n")

# Load JSON file
with open(os.path.join(ASSETS_PATH, "autosolve_narration.json"), "r", encoding="utf-8") as f:
    scripts = json.load(f)

# Create output directory
Path(os.path.join(OUTPUT_PATH, "lifelines")).mkdir(parents=True, exist_ok=True)

success_count = 0
skip_count = 0
error_count = 0
total_count = 0

def generate_audio(text, output_path):
    """Generate audio using Kokoro TTS"""
    global success_count, skip_count, error_count, total_count
    total_count += 1
    
    # Skip if exists
    if os.path.exists(output_path):
        print(f"[{total_count}] Skipping {os.path.basename(output_path)} (exists)")
        skip_count += 1
        return
    
    print(f"[{total_count}] Generating: {os.path.basename(output_path)}")
    
    try:
        # Generate audio using generator
        generator = pipeline(text, voice='af_heart', speed=1.0)
        audio_segments = []
        for item in generator:
            if len(item) == 3:
                graphemes, phonemes, audio = item
                audio_segments.append(audio)
        
        if not audio_segments:
            raise Exception("No audio generated")
        
        audio = audio_segments[0]
        
        # Create directory
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        
        # Save (Kokoro outputs at 24000 Hz)
        sf.write(output_path, audio, 24000)
        print(f"  [OK] Success")
        success_count += 1
    except Exception as e:
        print(f"  [ERR] Error: {e}")
        error_count += 1

# Process auto-solve narration
print("=== Processing Auto-Solve Narration ===\n")
narration = scripts.get("autosolve_narration", {}).get("files", {})

# Process intro (should already exist from lifeline generation)
print("Checking Intro Audio:")
intro_variants = narration.get("intro", {}).get("variants", [])
for variant in intro_variants:
    output_file = os.path.join(OUTPUT_PATH, "lifelines", variant["filename"])
    generate_audio(variant["text"], output_file)

# Process finding_group_intro
print("\nProcessing Finding Group Audio:")
finding_variants = narration.get("finding_group_intro", {}).get("variants", [])
for variant in finding_variants:
    output_file = os.path.join(OUTPUT_PATH, "lifelines", variant["filename"])
    generate_audio(variant["text"], output_file)

# Process before_submit
print("\nProcessing Confirmation Audio:")
confirm_variants = narration.get("before_submit", {}).get("variants", [])
for variant in confirm_variants:
    output_file = os.path.join(OUTPUT_PATH, "lifelines", variant["filename"])
    generate_audio(variant["text"], output_file)

print(f"\n\n=== Summary ===")
print(f"Generated: {success_count}")
print(f"Skipped: {skip_count}")
print(f"Errors: {error_count}")
print(f"Total: {total_count}")
