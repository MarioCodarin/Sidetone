# Roadmap

The product rule stays the same in every item below: **one primary action, quiet chrome, and nothing
leaves the Mac unless the user brings their own key for an optional feature.**

## Shipped in 1.1

- Redesigned panel: one record control, a live two-channel scope, one amber accent.
- First-run setup (permissions + recordings folder) and a user-chosen folder in Settings.
- Coalesced meters, allocation-free tap callback, cached library reads, structured logging.
- New icon, `build.sh --install`, a clean public history and docs.

## Next (small, high value)

1. **Mic toggle in setup.** The setup window explains the microphone but the on/off switch only
   lives in Settings; put it on the same row so "record only the call" is a first-run choice.
2. **Menu-bar clock.** Optionally show `12:34` next to the menu-bar glyph while recording, so the
   state is visible without opening the panel.
3. **End-of-meeting auto-stop.** Today the end-of-meeting alert asks; a preference could stop and
   save automatically a configurable grace period after the scheduled end.
4. **Search and notes.** A searchable recordings list with a short text note per take, stored next
   to the `.m4a` (never inside it), so a library of 200 takes stays usable.
5. **Recover-all.** A single "Mix all unfinished" action for folders left behind by crashes.
6. **Shortcuts / URL actions.** `sidetone://record`, `stop`, `pause`, `status` (and App Intents) so
   Stream Deck, Shortcuts and scripts can drive it without the menu bar.

## Later (bigger bets)

7. **Optional transcription with the user's own key.** Off by default, key stored in the macOS
   Keychain, audio sent only when the user presses "Transcribe". This is the one feature that would
   justify a key field; it must never become a silent upload. Until then, the app intentionally has
   no keys to configure.
8. **Channel routing options.** Keep the default hard split (L = call, R = you), add "two mono files"
   and "centered mix" for people who want a single-ear friendly file.
9. **Quality controls.** AAC bitrate choice, and a lossless FLAC option for archival takes.
10. **Distribution.** Notarized, signed release plus a Homebrew cask so updating does not reset the
    macOS privacy grants (TCC keys on the code signature).

## Explicit non-goals

- Accounts, cloud storage, telemetry, or a subscription.
- Screen recording: Sidetone captures audio only, which is why it asks for Audio Recording and not
  Screen Recording.
- A Dock icon or a document window: this is a menu-bar utility, and closing its windows must never
  quit it.
