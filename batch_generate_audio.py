"""
Batch audio generation using Kokoro TTS
Run this script from the Ishans_games_4 directory
"""
import json
import sys
import os
from pathlib import Path

# Add kokoro to path
sys.path.insert(0, r"D:\kokoro")

from kokoro import KPipeline
import soundfile as sf

print("Loading Kokoro TTS...")
pipeline = KPipeline(lang_code='a')
print("Kokoro loaded!\n")

# Load tasks
with open("audio_tasks.json", "r", encoding="utf-8") as f:
    tasks = json.load(f)

success_count = 0
skip_count = 0
error_count = 0

for i, task in enumerate(tasks, 1):
    output_path = task["output"]
    text = task["text"]
    
    # Skip existing
    if os.path.exists(output_path):
        print(f"[{i}/{len(tasks)}] Skipping {output_path} (exists)")
        skip_count += 1
        continue
    
    print(f"[{i}/{len(tasks)}] Generating: {output_path}")
    
    try:
        # Generate audio using generator
        generator = pipeline(text, voice='af_heart', speed=1.0)
        audio_segments = []
        for item in generator:
            # Generator yields (graphemes, phonemes, audio)
            if len(item) == 3:
                graphemes, phonemes, audio = item
                audio_segments.append(audio)
            else:
                print(f"  ! Unexpected generator item: {type(item)}")
        
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

print(f"\n=== Summary ===")
print(f"Generated: {success_count}")
print(f"Skipped: {skip_count}")
print(f"Errors: {error_count}")
print(f"Total: {len(tasks)}")
