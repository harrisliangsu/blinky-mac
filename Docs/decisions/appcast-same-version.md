# Same version, new enclosure

**Status:** still in force. **Evidence:** Pulse 1.4.0, Release runs 35854912103 and 35854920796.

Sparkle refuses an archive whose EdDSA signature does not match the zip it downloaded. The Chinese dialog is «更新错误！此更新未正确签名，无法验证其真实性。» The public key in this fork was fine: Pulse 1.3.2 verified. 1.4.0 did not, because the feed and the release asset were two different zips.

`v1.4.0` was pushed twice (lightweight tag, then annotated). Both runs started the Release workflow. The first uploaded a zip, signed that zip, and committed `Offer 1.4.0 to Sparkle` (`02bff99`). The second ran `gh release upload --clobber`, which replaced the zip with another build of the same version — the build is not reproducible — and `Scripts/appcast.py` then printed `appcast.xml already carries 1.4.0 — leaving it alone.` The enclosure stayed the signature of zip A. The download was zip B (`sha256 3893332903abeace16f915a142b11e983bf772b3b590cd253b7c3040c8c13c69`).

The writer used to treat “this version is already in the feed” as “do nothing”, on the grounds that an entry which has been served must not change. It does not hold for the version just built. That item's enclosure (`url`, `length`, `sparkle:edSignature`) is rewritten from the zip passed in. Notes stay. The feed keeps that one item (`KEPT_ITEMS` in `Scripts/appcast.py`). Older items are omitted, so they are not re-signed and their notes are not shown under the version being offered. [../releasing.md](../releasing.md)

Both halves are required. A concurrency group alone still ships a broken feed if the second run clobbers the asset and the writer no-ops. A writer that rewrites the enclosure, without the group, can still lose the race: both runs read `main`, both commit on `offer-sparkle-<version>`, and the push that lands can be the signature of a zip the other run has already replaced. `release.yml` therefore queues (`cancel-in-progress: false`) so the waiting run publishes its zip and then re-offers it on that branch. The offer is a pull request. The workflow does not push `main`. Cancelling the in-progress run would stop mid-upload.

The 1.4.0 enclosure in `appcast.xml` was not edited in the change that records this. It has to be signed in CI, with `SPARKLE_PRIVATE_KEY`, against the zip that is actually on the release — one `workflow_dispatch` of Release for `v1.4.0`, after the writer above is on `main`.

Current: [../releasing.md](../releasing.md).
