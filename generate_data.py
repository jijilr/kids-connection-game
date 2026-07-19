#!/usr/bin/env python3
"""
Taxonomic Data Generator using DeepSeek API.
Generates items with rich tag vectors and multiple classification dimensions.
"""

import json
import os
import sys
import time
import requests

# Load API key from Hermes .env
ENV_PATH = os.path.expanduser("~/AppData/Local/hermes/.env")
API_KEY = None
if os.path.exists(ENV_PATH):
    for line in open(ENV_PATH).readlines():
        line = line.strip()
        if line.startswith("DEEPSEEK_API_KEY="):
            API_KEY = line.split("=", 1)[1].strip().strip('"').strip("'")
            break

if not API_KEY:
    print("ERROR: DEEPSEEK_API_KEY not found in .env", file=sys.stderr)
    sys.exit(1)

DEEPSEEK_URL = "https://api.deepseek.com/v1/chat/completions"

PROMPT = """You are building a taxonomic classification game for children aged 8-12. 
Generate data for the domain: DINOSAURS AND PREHISTORIC CREATURES.

Output as JSON only (no markdown, no explanation). The JSON must have this structure:

{
  "domain": "prehistoric_life",
  "items": [
    {
      "id": "item_01",
      "name": "T-Rex",
      "imagePrompt": "Cute cartoon T-Rex, large head, tiny arms, sharp teeth, flat vector art",
      "funFact": "T-Rex had teeth as long as bananas!",
      "tags": ["carnivore", "extinct", "cretaceous", "land", "large", "bipedal", "theropod"]
    }
  ],
  "dimensions": [
    {
      "key": "diet",
      "displayName": "Diet Type",
      "question": "What do they eat?",
      "values": {
        "carnivore": {"displayName": "Meat-Eaters", "color": "#E74C3C"},
        "herbivore": {"displayName": "Plant-Eaters", "color": "#2ECC71"},
        "omnivore": {"displayName": "Eats Both", "color": "#F39C12"}
      }
    },
    {
      "key": "era",
      "displayName": "Geological Era",
      "question": "When did they live?",
      "values": {
        "triassic": {"displayName": "Triassic", "color": "#9B59B6"},
        "jurassic": {"displayName": "Jurassic", "color": "#3498DB"},
        "cretaceous": {"displayName": "Cretaceous", "color": "#E67E22"}
      }
    }
  ]
}

REQUIREMENTS:
- Generate EXACTLY 24 items covering diverse prehistoric creatures (dinosaurs, pterosaurs, marine reptiles, early mammals, etc.)
- Every item MUST have ALL tag values defined in the dimensions (each tag = a dimension value)
- Dimensions to include:
  1. "living_status" (values: "extinct", "alive_today") — if alive_today, use modern animals related to prehistoric ones
  2. "diet" (values: "carnivore", "herbivore", "omnivore")
  3. "era" (values: "triassic", "jurassic", "cretaceous", "modern")
  4. "habitat" (values: "land", "water", "air")
  5. "size" (values: "small", "medium", "large")
  6. "locomotion" (values: "bipedal", "quadrupedal", "swimming", "flying")
  7. "category" (values: "dinosaur", "pterosaur", "marine_reptile", "early_mammal", "insect", "plant")

- Make sure tags on each item MATCH the dimension values listed above.
- Image prompts should be consistent style: "Cute cartoon [name], flat vector art, bright colors, white background, for children"
- Fun facts should be genuinely interesting for kids, 1-2 sentences.
- Ensure roughly balanced distribution so each dimension value has at least 2-3 items.

OUTPUT ONLY VALID JSON. No explanation, no markdown fences."""

def call_deepseek(prompt, max_retries=3):
    headers = {
        "Authorization": f"Bearer {API_KEY}",
        "Content-Type": "application/json"
    }
    
    for attempt in range(max_retries):
        try:
            response = requests.post(
                DEEPSEEK_URL,
                headers=headers,
                json={
                    "model": "deepseek-chat",
                    "messages": [
                        {"role": "system", "content": "You are a precise data generator. Output only valid JSON. No markdown, no explanation."},
                        {"role": "user", "content": prompt}
                    ],
                    "temperature": 0.7,
                    "max_tokens": 8000
                },
                timeout=120
            )
            response.raise_for_status()
            data = response.json()
            content = data["choices"][0]["message"]["content"].strip()
            
            # Strip markdown code fences if present
            if content.startswith("```"):
                lines = content.split("\n")
                content = "\n".join(lines[1:-1])
            
            return json.loads(content)
        except Exception as e:
            print(f"Attempt {attempt+1} failed: {e}", file=sys.stderr)
            if attempt < max_retries - 1:
                time.sleep(2 ** attempt)
    
    raise Exception("All retries failed")

def validate_data(data):
    """Basic validation of generated data."""
    errors = []
    
    if "items" not in data:
        errors.append("Missing 'items' key")
        return errors
    
    items = data["items"]
    dimensions = data.get("dimensions", [])
    
    if len(items) < 16:
        errors.append(f"Only {len(items)} items, need at least 16")
    
    # Check each item has all dimension tags
    dim_keys = {d["key"] for d in dimensions}
    dim_values = {}
    for d in dimensions:
        dim_values[d["key"]] = set(d.get("values", {}).keys())
    
    for item in items:
        tags = set(item.get("tags", []))
        for dim_key in dim_keys:
            if dim_key in dim_values:
                match = tags & dim_values[dim_key]
                if not match:
                    errors.append(f"Item '{item.get('name')}' missing tag for dimension '{dim_key}'")
    
    # Check balance
    for dim_key, values in dim_values.items():
        for val in values:
            count = sum(1 for item in items if val in item.get("tags", []))
            if count < 2:
                errors.append(f"Dimension '{dim_key}' value '{val}' has only {count} items")
    
    return errors


if __name__ == "__main__":
    print("Generating taxonomic data via DeepSeek...", file=sys.stderr)
    
    try:
        data = call_deepseek(PROMPT)
        
        errors = validate_data(data)
        if errors:
            print("\n⚠️  Validation warnings:", file=sys.stderr)
            for e in errors:
                print(f"  - {e}", file=sys.stderr)
        
        output_path = os.path.join(os.path.dirname(__file__), "taxonomic_data.json")
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        
        print(f"\n✅ Generated {len(data['items'])} items with {len(data.get('dimensions', []))} dimensions", file=sys.stderr)
        print(f"📁 Saved to: {output_path}", file=sys.stderr)
        
        # Print summary
        print("\n📊 Summary:", file=sys.stderr)
        for d in data.get("dimensions", []):
            vals = {}
            for item in data["items"]:
                for v in d.get("values", {}):
                    if v in item.get("tags", []):
                        vals[v] = vals.get(v, 0) + 1
            print(f"  {d['displayName']}: {vals}", file=sys.stderr)
            
        # Output the path for the next step
        print(output_path)
        
    except Exception as e:
        print(f"❌ Failed: {e}", file=sys.stderr)
        sys.exit(1)
