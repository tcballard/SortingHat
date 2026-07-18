# Native Finder Quick Action

Sorting Hat ships **Send to Sorting Hat** as a non-UI Finder Action Extension.
Finder is an intake surface only: rules, the Inbox, Activity, review, repair, and
failure dismissal remain in the main app.

## Behaviour

- The action is copy-only intake. It accepts one or more files and never moves,
  renames, modifies, or deletes an original.
- Each selected file is copied into a durable App Group queue. The extension
  completes only after staging succeeds; it does not launch Sorting Hat, invoke
  a model, or write directly to the configured Inbox.
- If Sorting Hat is running, its intake coordinator normally drains the queue
  within one second. Pausing Sorting Hat pauses filing, not intake, so files
  still arrive in the Inbox and wait there.
- If Sorting Hat is closed, the Finder action completes after its copy is
  durably staged. The app drains that queue on its next launch.
- File validation and collision naming are shared with the dashboard's **Add
  Files** command. Queue handoff uses a hidden temporary file, a persisted
  commit state, and a delivery receipt. Kernel-released cross-process locks
  serialize ingress/recovery separately from Inbox draining and recovery
  controls. A live large-file copy cannot be mistaken for a crash, while
  Finder staging never waits on slow Inbox I/O. Interrupted staging is
  recovered on the next pass when complete, or quarantined with a visible
  failure when incomplete.
- Staged-copy and provider failures remain visible under **Settings → Finder**.
  **Retry** makes a failed queued copy eligible for another delivery attempt;
  **Remove** discards only Sorting Hat's staged copy after confirmation. Neither
  action changes the Finder original.
- One invocation accepts at most 256 files. The extension processes them
  sequentially with a 256 MB per-file limit, a 1 GB selection limit, and a
  25-second request deadline. It reports every filename left unqueued;
  already staged successes remain safe when another item fails. Larger files
  can still use **Add Files** inside Sorting Hat, which is not constrained by
  the Finder extension's lifetime.

The extension uses Apple's `com.apple.services` action-extension point and
`NSItemProvider` file representations. It never requests Full Disk Access and
never moves or deletes a selected Finder item. This follows Apple's
[Finder Action Extension sample](https://developer.apple.com/documentation/appkit/add-functionality-to-finder-with-action-extensions),
[App Group guidance](https://developer.apple.com/documentation/xcode/configuring-app-groups),
and [sandbox file-access guidance](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).

The App Group contains only the extension-to-app queue, manifests, receipts,
and diagnostics needed for handoff. Access to the configured Inbox uses a
security-scoped bookmark stored in the main app's private Application Support
directory, not in the App Group. The extension therefore cannot read the Inbox
or its bookmark. If the Inbox path changes or access becomes stale, delivery
stops safely until **Settings → Finder → Repair Inbox Access** succeeds.

## Enable it

macOS disables newly installed Action Extensions until the user enables them.
Open **System Settings → General → Login Items & Extensions → Finder**, enable
**Send to Sorting Hat**, then use it from Finder's **Quick Actions** menu.

Sorting Hat reports whether the extension is embedded, whether the shared
container is available, the last invocation, queued items, Inbox permission,
and recent intake failures in **Settings → Finder**. macOS does not provide a
reliable public API for an app to query the action's enabled state, so that
status deliberately does not claim that Finder has enabled it. Registration
checks are not enough: every installed build must be verified by selecting a
safe fixture in Finder and invoking **Quick Actions → Send to Sorting Hat** from
the right-click menu.

## Legacy Automator migration

Older installs may contain:

```text
~/Library/Services/Send to Sorting Hat.workflow
```

Sorting Hat will not remove it automatically. **Retire Legacy Action** becomes
available only after the current app build has an immutable native invocation
record, matching delivery receipts, no pending staged copies, and no unresolved
delivery failure for that invocation. It then moves the workflow into an
Application Support backup; it does not delete it or modify any selected file.

Migration is reversible from **Settings → Finder → Restore Legacy Action**.
Finder may need to be refreshed before a retired or restored action disappears
or reappears in its Quick Actions menu.

## Signing requirement

The app and extension use the macOS App Group
`R8HXTBY3NM.com.tcballard.sortinghat`. Both bundles must be signed by Team
`R8HXTBY3NM`, with the extension signed before the containing app. An ad-hoc
build can exercise the app and core tests, but macOS will not grant its Finder
extension the product App Group. Installed Finder verification therefore needs
the project's Developer ID certificate; there is no shell-script or Automator
fallback. The current Xcode project explicitly builds `arm64`, so this milestone
supports Apple-silicon Macs only.
