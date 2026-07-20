# App Privacy submission guidance

This is a conservative preparation note, not a substitute for the account holder's attestation in App Store Connect.

## Shipping behavior that is clear

- Sorting Hat has no advertising SDK and does not track users across apps or websites.
- The developer does not operate an analytics, account, or file-processing service for the app.
- Apple Foundation Models and document/image extraction operate on the Mac when the on-device Apple provider is selected.
- Ollama sends extracted context to the exact server URL configured by the user.
- OpenAI sends extracted file context and the user's API credential to OpenAI when configured and selected or used as a fallback.

## Decision required before answering the questionnaire

### Recommended privacy-first Store build

Remove remote-capable providers from the Mac App Store target, leaving Apple's on-device provider and local-only Ollama if its URL is technically constrained to loopback. With no third-party retention path, confirm the final binary and then select **Data Not Collected**.

### If OpenAI remains available

Do not select **Data Not Collected**. A conservative disclosure is:

- Data type: **Other User Content**
- Purpose: **App Functionality**
- Linked to the user: **Yes**, because OpenAI authenticates the request to the user's API account
- Used for tracking: **No**

The account holder should also review whether **User ID** must be disclosed because the API credential authenticates an identifiable OpenAI account. Confirm OpenAI's current retention terms immediately before submission.

For Ollama, the answer depends on whether the Store build permits non-loopback URLs. A user-controlled local server normally does not mean the developer collects data, but a remotely hosted Ollama-compatible endpoint can retain content. Constraining Store builds to loopback removes that ambiguity.

## Privacy policy URL

https://github.com/tcballard/SortingHat/blob/main/docs/privacy.md
