# Audio Generation Script for Kokoro TTS
# Run this from D:\kokoro directory with proper environment

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
