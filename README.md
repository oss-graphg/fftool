# 🎬 FFtool — Interactive FFmpeg Helper

A terminal-based interactive wrapper for FFmpeg. No more googling commands every single time.

Pick what you want to do → answer a few questions → done. The script shows you the exact FFmpeg command before running it, so you can actually learn FFmpeg while using it.

## 🎥 Preview
```bash
╔══════════════════════════════════════╗
║ 🎬 FFtool — FFmpeg Helper ║
╚══════════════════════════════════════╝

File: video.mp4

What do you want to do?

    🔄 Convert video
    🎵 Convert audio
    🖼️ Convert image
    📦 Compress (reduce file size)
    ⏩ Change speed
    ✂️ Cut/trim
    🔊 Extract audio from video
    📊 File info
    🧰 Extras (screenshots, rotate, FPS...)

f) Change input file
q) Quit
```
## Manual
```bash
# Clone the repo
git clone https://github.com/oss-graphg/fftool.git
cd fftool

# Make it executable
chmod +x fftool.sh

# Option A: Run directly
./fftool.sh

# Option B: Symlink to PATH (available everywhere)
sudo ln -s "$(pwd)/fftool.sh" /usr/local/bin/fftool

# Option C: Copy to PATH
cp fftool.sh ~/.local/bin/fftool
```
#### I personally made an alias to open it :)

## Dependencies
The script checks for dependencies on first run and offers to install them automatically.
| Dependency | Purpose                                    |
| ---------- | ------------------------------------------ |
| `ffmpeg`   | Core media processing (includes `ffprobe`) |
| `bc`       | Math calculations (file size, bitrate)     |
| `python3`  | Atempo chain calculation for speeds >2x    |

If anything is missing, you'll see:
```text
╔══════════════════════════════════════╗
║       Missing dependencies!          ║
╚══════════════════════════════════════╝

Missing commands: bc ffmpeg
Packages to install: bc ffmpeg
Detected system: pacman
Command: sudo pacman -S --noconfirm bc ffmpeg

[?] Install? [Y/n]:
```

## 🤝 Contributing

Found a bug? Have an idea? **Please** open an issue!

## 🐛 Reporting Bugs
When reporting, please include:
```text
    Your distro and version (cat /etc/os-release)
    FFmpeg version (ffmpeg -version | head -1)
    What you did (which menu options you chose)
    What happened vs. what you expected
    The FFmpeg command that was shown (the script always prints it)
```

## 📋 FFmpeg Flags Cheat Sheet
Since this tool is meant to help you learn FFmpeg, here's a quick reference:

```text

-c:v    → codec: video          (e.g., libx264, libx265, libvpx-vp9)
-c:a    → codec: audio          (e.g., aac, libmp3lame, libopus)
-c copy → copy streams without re-encoding (instant, no quality loss)
-b:v    → bitrate: video        (e.g., 5M)
-b:a    → bitrate: audio        (e.g., 320k)
-vf     → video filter          (e.g., scale=1920:1080)
-af     → audio filter          (e.g., atempo=1.25)
-vn     → no video              (strip video, keep audio)
-an     → no audio              (strip audio, keep video)
-crf    → quality factor        (lower = better, 18-28 typical)
-ss     → seek/start time
-to     → end time
-t      → duration
```

## 📜 License
MIT — do whatever you want with it. But I would be very happy if You could mention me in Your work!

## ⭐ Star History
If this saved you from googling "ffmpeg convert mp4 to mp3" for the 47th time, consider giving it a ⭐.
