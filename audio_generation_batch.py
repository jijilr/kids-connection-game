"""
Generate batch files to create audio using Kokoro TTS.
This creates individual scripts that can be run when the environment is working.
"""
import json
import os
from pathlib import Path

# Paths
ASSETS_PATH = r"Assets\audio_scripts"
OUTPUT_PATH = r"Assets\audio"
BATCH_OUTPUT = r"generate_audio_batch.txt"

# Load JSON files
with open(os.path.join(ASSETS_PATH, "educational_facts.json"), "r", encoding="utf-8") as f:
    educational_facts = json.load(f)

with open(os.path.join(ASSETS_PATH, "general_and_categories.json"), "r", encoding="utf-8") as f:
    general_and_categories = json.load(f)

# Collect all audio to generate
audio_tasks = []

def add_task(text, output_file, category="general"):
    audio_tasks.append({
        "text": text,
        "output": f"{OUTPUT_PATH}\\{output_file}",
        "category": category
    })

# Process general feedback
feedback = general_and_categories["general_feedback"]
for category, items in feedback.items():
    for item in items:
        add_task(item["text"], f"feedback/{item['id']}.mp3", "feedback")

# Process item names
items = general_and_categories["item_names"]
for item in items:
    add_task(item["text"], f"names/{item['id']}.mp3", "names")

# Process category success
categories = general_and_categories["category_success"]
for category, items in categories.items():
    for item in items:
        add_task(item["text"], f"categories/{item['id']}.mp3", "categories")

# Process educational facts
facts = educational_facts["educational_facts"]
for item_name, item_data in facts.items():
    # About facts
    if "about" in item_data:
        for fact in item_data["about"]:
            add_task(fact["text"], f"educational/{fact['id']}.mp3", "educational")
    
    # Not_X corrections
    for key, value in item_data.items():
        if key.startswith("not_"):
            add_task(value["text"], f"educational/{value['id']}.mp3", "educational")

print(f"Total audio files to generate: {len(audio_tasks)}")

# Save as JSON for batch processing
with open("audio_tasks.json", "w", encoding="utf-8") as f:
    json.dump(audio_tasks, f, indent=2, ensure_ascii=False)

print(f"Saved audio tasks to audio_tasks.json")

# Create PowerShell script
ps_script = """# Audio Generation Script for Kokoro TTS
# Run this from D:\\kokoro directory with proper environment

$tasks = Get-Content "audio_tasks.json" | ConvertFrom-Json

foreach ($task in $tasks) {
    $output = $task.output
    $text = $task.text
    
    # Skip if exists
    if (Test-Path $output) {
        Write-Host "Skipping $output (exists)" -ForegroundColor Yellow
        continue
    }
    
    Write-Host "Generating: $output" -ForegroundColor Cyan
    
    # Create directory if needed
    $dir = Split-Path $output
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    
    # Run Kokoro TTS (adjust command based on your setup)
    python kokoro_tts.py "$text" "$output" --voice af_heart
}

Write-Host "Audio generation complete!" -ForegroundColor Green
"""

with open("generate_all_audio.ps1", "w", encoding="utf-8") as f:
    f.write(ps_script)

print("Created PowerShell script: generate_all_audio.ps1")

# Create Python script using kokoro directly
py_script = '''"""
Batch audio generation using Kokoro TTS
Run this script from the Ishans_games_4 directory
"""
import json
import sys
import os
from pathlib import Path

# Add kokoro to path
sys.path.insert(0, r"D:\\kokoro")

from kokoro import KPipeline
import soundfile as sf

print("Loading Kokoro TTS...")
pipeline = KPipeline(lang_code='a', voice='af_heart')
print("Kokoro loaded!\\n")

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
        # Generate audio
        audio, sample_rate = pipeline(text, voice='af_heart', speed=1.0)
        
        # Create directory
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        
        # Save
        sf.write(output_path, audio, sample_rate)
        print(f"  ✓ Success")
        success_count += 1
    except Exception as e:
        print(f"  ✗ Error: {e}")
        error_count += 1

print(f"\\n=== Summary ===")
print(f"Generated: {success_count}")
print(f"Skipped: {skip_count}")
print(f"Errors: {error_count}")
print(f"Total: {len(tasks)}")
'''

with open("batch_generate_audio.py", "w", encoding="utf-8") as f:
    f.write(py_script)

print("Created Python script: batch_generate_audio.py")
print("\nTo generate audio:")
print("1. Fix the transformers/torchvision conflict in your conda environment")
print("2. Run: python batch_generate_audio.py")
