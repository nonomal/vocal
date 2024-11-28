# Vocal - A Free MacOS Native YouTube Video Transcriber

![image](https://github.com/user-attachments/assets/3b0ce33e-5dca-4c42-98d4-5de55e1dea2b)

A minimal, native macOS app that transcribes YouTube videos and local video files with exceptional accuracy. Simple, fast, and elegant.

## ✨ Features
- **Easy YouTube Integration**: Just paste (⌘V) any YouTube URL
- **Local Video Support**: Drag & drop or click to upload local video files
- **Smart Formatting**: Automatically formats transcriptions into readable paragraphs
- **Multiple Export Options**: Copy or save transcriptions with a single click
- **Progress Tracking**: Real-time progress bars for both download and transcription
- **Native Performance**: Built with SwiftUI for optimal macOS integration
- **Dark and Light Modes**: Seamless integration with your system preferences

## 💻 Get Started

### To use Vocal, you can follow these quick steps to set up the app on your macOS system.

	1.	Download the App: Get the latest version from the releases page.
	2.	Install Prerequisites: Vocal requires Python, Homebrew, and yt-dlp for downloading and processing YouTube videos.

### Setting Up Prerequisites for YouTube Videos (Local videos have no requirements)

### Install Python

To install Python on macOS, open your Terminal and use the following command:

```bash
brew install python
```

### Install Homebrew

If you don’t have Homebrew, you can install it by running:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### Install yt-dlp

Finally, install yt-dlp using Homebrew:

```bash
brew install yt-dlp
```

	3.	Launch Vocal: Once prerequisites are installed, open Vocal and transcribe your videos!


## 🛠️ Technical Details
- Built with SwiftUI and AVFoundation
- Uses Apple's Speech Recognition framework for high-quality transcription
- Integrated with yt-dlp for reliable YouTube video downloading
- Native macOS window management and system integration

## 🎯 Use Cases
- **Content Creation**: Quickly transcribe video content for blogs or articles
- **Research**: Convert video interviews or lectures into searchable text
- **Accessibility**: Make video content accessible through text
- **Note Taking**: Transform video lessons into written notes

## 🤝 Contributing
We welcome contributions! Here's how you can help:

1. Clone the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

Please ensure your PR:
- Maintains the minimal, focused design philosophy
- Follows the existing code style
- Includes appropriate tests
- Updates documentation as needed

## 🎯 Roadmap
- Multi-language support
- Timestamp support
- Advanced export formats (PDF, SRT, VTT)
- Video mini-player while transcribing
- Quick edit mode for transcriptions

## 📝 License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links
- Website: [Nuanc.me](https://nuanc.me)
- Report issues: [GitHub Issues](https://github.com/nuance-dev/Vocal/issues)
- Follow updates: [@Nuancedev](https://twitter.com/Nuancedev)

## 💝 Acknowledgments
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) for YouTube video downloading
- Apple's Speech Recognition framework for transcription
- The open source community for inspiration and support
