# App Review notes

Sorting Hat does not require sign-in, an account, a subscription, or credentials supplied by the developer.

The app is a menu-bar accessory with a normal dashboard. The dashboard opens on launch and when the menu-bar hat is left-clicked. Right-clicking the hat opens its quick menu.

## Suggested review path

1. Launch Sorting Hat.
2. During setup, choose an empty temporary folder as the Inbox and another as the filed-output folder.
3. Describe a filing plan such as: “Put receipts in Finance/Receipts/YYYY-MM and put everything else in Sorted/YYYY-MM. Give every file a short descriptive name.” Review and save the proposed rules.
4. Add a small text or PDF fixture from the Inbox view, or copy it into the selected Inbox.
5. Ensure the hat is running, then choose Sort Now if needed.
6. Open Activity to see the renamed file and destination. An uncertain or invalid result remains available for manual review.

On a supported Mac running macOS 26 with Apple Intelligence enabled, choose the Apple provider and “On this Mac” to exercise local generation. Ollama and OpenAI are optional and do not need to be configured for review when the Apple model is available.

The App Sandbox limits access to user-selected folders. Security-scoped bookmarks preserve that access across relaunch. The bundled Finder Action uses the shared App Group only to copy explicitly selected Finder items into Sorting Hat's intake queue; it does not modify the originals.

To test the Finder Action, open **System Settings → General → Login Items & Extensions → Finder**, enable **Send to Sorting Hat**, then select a small file in Finder and choose **Quick Actions → Send to Sorting Hat**. The file should appear as a copy in Sorting Hat's Inbox and then be processed while the app is running.

The app does not require a network connection when Apple's on-device provider is available and selected. Optional OpenAI and Ollama settings may be left blank.

## Review contact

- Name: Tom Ballard
- Email: tom@armytage.co
- Phone: owner entry required in App Store Connect
