# App Review Notes

Use this text in App Store Connect Review Notes.

```text
scrshot is a menu bar-only macOS utility. After launch, the app appears as a camera icon in the macOS menu bar and does not show a Dock icon.

How to review the core flow:

1. Launch scrshot.
2. Open the scrshot menu bar icon.
3. Press Cmd+Shift+1 to start a screenshot capture.
4. Grant Screen Recording access if macOS prompts for it.
5. Complete the screenshot editor by choosing Done.
6. On first save, scrshot opens a standard folder picker. Choose a user-accessible local folder, such as Desktop or Documents. The app saves screenshots there and stores a security-scoped bookmark for future saves.
7. To test recording, open the menu bar icon and choose Start Screen Recording. If no save folder has been selected yet, choose a user-accessible local folder when prompted. The menu bar icon changes to a filled recording symbol while recording is active. Choose Stop Screen Recording to finish.

Privacy-sensitive behavior:

- Screen content is captured only after the user starts a screenshot or recording.
- Microphone audio is captured only when the user selects Microphone Only or System + Microphone recording audio.
- System audio is captured only when the user selects System Audio or System + Microphone recording audio.
- Screenshots and recordings are saved locally only to the user-selected folder, not to the app container.
- The app does not upload captures, recordings, audio, preferences, diagnostics, or analytics to a server.

No login, account, subscription, in-app purchase, or external service is required.
```

## App Store Connect Privacy Answers

Use these answers as the basis for App Privacy metadata:

- Tracking: No.
- Third-party advertising: No.
- Analytics collection: No.
- Data linked to user: No.
- Data used to track user: No.
- User content: The app processes user-initiated screenshots and recordings locally only. Do not mark this as collected unless App Store Connect asks about local-only processing separately.
- Audio data: The app processes optional system audio and microphone audio locally only during recording modes selected by the user. Do not mark this as collected unless App Store Connect asks about local-only processing separately.

The public privacy policy URL should point to:

```text
https://github.com/Warrfie/scrshot/releases/download/v1.2/PRIVACY.md
```
