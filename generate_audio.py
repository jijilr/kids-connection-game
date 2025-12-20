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

# Initialize Kokoro pipeline
print("Initializing Kokoro TTS...")
pipeline = KPipeline(lang_code='a', voice='af_heart')
print("Kokoro TTS initialized!")

# Load JSON files
with open(os.path.join(ASSETS_PATH, "educational_facts.json"), "r", encoding="utf-8") as f:
    educational_facts = json.load(f)

with open(os.path.join(ASSETS_PATH, "general_and_categories.json"), "r", encoding="utf-8") as f:
    general_and_categories = json.load(f)

# Create output directories
Path(OUTPUT_PATH).mkdir(parents=True, exist_ok=True)
Path(os.path.join(OUTPUT_PATH, "educational")).mkdir(exist_ok=True)
Path(os.path.join(OUTPUT_PATH, "feedback")).mkdir(exist_ok=True)
Path(os.path.join(OUTPUT_PATH, "categories")).mkdir(exist_ok=True)
Path(os.path.join(OUTPUT_PATH, "names")).mkdir(exist_ok=True)

def generate_audio(text, output_file, voice="af_heart"):
    """Generate audio using Kokoro TTS"""
    output_path = os.path.join(OUTPUT_PATH, output_file)
    
    # Skip if file already exists
    if os.path.exists(output_path):
        print(f"Skipping {output_file} (already exists)")
        return
    
    print(f"Generating: {output_file}")
    
    try:
        # Generate audio using Kokoro pipeline
        audio, sample_rate = pipeline(text, voice=voice, speed=1.0)
        
        # Ensure output directory exists
        os.makedirs(os.path.dirname(output_path), exist_ok=True)
        
        # Save as MP3 (or WAV if MP3 not supported)
        sf.write(output_path, audio, sample_rate)
        print(f"✓ Created: {output_file}")
    except Exception as e:
        print(f"✗ Error generating {output_file}: {e}")

def process_educational_facts():
    """Process all educational facts"""
    print("\n=== Processing Educational Facts ===")
    facts = educational_facts["educational_facts"]
    
    for item_name, item_data in facts.items():
        print(f"\nProcessing: {item_name}")
        
        # Process 'about' facts
        if "about" in item_data:
            for fact in item_data["about"]:
                output_file = f"educational/{fact['id']}.mp3"
                generate_audio(fact["text"], output_file)
        
        # Process 'not_X' corrections
        for key, value in item_data.items():
            if key.startswith("not_"):
                output_file = f"educational/{value['id']}.mp3"
                generate_audio(value["text"], output_file)

def process_general_feedback():
    """Process general feedback messages"""
    print("\n=== Processing General Feedback ===")
    feedback = general_and_categories["general_feedback"]
    
    for category, items in feedback.items():
        print(f"\nProcessing: {category}")
        for item in items:
            output_file = f"feedback/{item['id']}.mp3"
            generate_audio(item["text"], output_file)

def process_item_names():
    """Process item names"""
    print("\n=== Processing Item Names ===")
    items = general_and_categories["item_names"]
    
    for item in items:
        output_file = f"names/{item['id']}.mp3"
        generate_audio(item["text"], output_file)

def process_category_success():
    """Process category success messages"""
    print("\n=== Processing Category Success Messages ===")
    categories = general_and_categories["category_success"]
    
    for category, items in categories.items():
        print(f"\nProcessing: {category}")
        for item in items:
            output_file = f"categories/{item['id']}.mp3"
            generate_audio(item["text"], output_file)

if __name__ == "__main__":
    print("Starting audio generation...")
    print(f"Kokoro path: {KOKORO_PATH}")
    print(f"Output path: {OUTPUT_PATH}")
    
    # Process all content
    process_general_feedback()
    process_item_names()
    process_category_success()
    process_educational_facts()
    
    print("\n=== Audio Generation Complete! ===")
