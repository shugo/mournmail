---
name: release
description: Cut a release -- check main, run rake bump, watch the gem go out
---

Release what is on `main`: bump the version, tag it, push, and report when
RubyGems.org has it.  A release cannot be taken back, so every step looks
before it acts.

The mechanism is `bundle exec rake bump` (the task in the Rakefile, the
same one Textbringer has) followed by `.github/workflows/push_gem.yml`,
which the tag triggers.  Do not use `bundle exec rake release`: it pushes
the gem from the local machine, which has no RubyGems.org credentials here,
and the tag it pushes first triggers the workflow, which publishes the same
gem through trusted publishing; v3 was cut that way and the workflow run
failed.

1. Look first.  Every one of these has to hold, and the skill stops and
   says which does not rather than releasing around it:
   - `git branch --show-current` is `main`.  Releases are cut from there;
     `rake bump` checks `main` out itself, but a switch mid-release is a
     surprise, not a step.
   - `git status --short` is clean.  `rake bump` commits with `-a`, so any
     tracked change lying in the tree would go into the version commit;
     commit it (the `push` skill) or set it aside.
   - `git fetch origin` and then `git rev-parse HEAD origin/main` agree.
     `rake bump` pulls, so a remote ahead of HEAD would be released without
     having been looked at.
   - CI is green for HEAD: `gh run list --workflow test.yml --commit
     $(git rev-parse HEAD) --limit 1` says `completed success`.  Queued or
     running is not green yet -- start one background wait on its
     conclusion, as the `push` skill does, and take the release up when it
     lands.  Red is a stop.

2. Know what is being released.  Since v2 the version is a single integer
   (`VERSION = "3"`) and `rake bump` adds one, so the next version is the
   last tag plus one:

       git describe --tags --abbrev=0
       git log --oneline $(git describe --tags --abbrev=0)..HEAD

   Read the subjects, and the bodies where a subject leaves it open, and
   name in the report the commits the release carries.  When the history
   since the last tag is only documentation and housekeeping, ask whether
   a release is wanted at all rather than cutting one for nothing.

3. Bump, tag and push, which one command does:

       bundle exec rake bump

   It checks out `main`, pulls, rewrites `lib/mournmail/version.rb`,
   commits that one file with the subject `Bump version to <N>` -- the way
   every release commit here reads, with no trailer -- pushes, tags the
   commit `v<N>`, and pushes the tag.  Check its work: `git show --stat
   HEAD` names version.rb alone, `git tag --points-at HEAD` names the tag,
   and `git ls-remote --tags origin v<N>` shows it on the remote.  If the
   task stopped partway, report exactly which of those steps happened and
   do not repeat it blindly: a pushed tag is already a release.  Never
   force-push here: a tag that reached the remote is what the workflow
   released, and rewriting it would release something else under the same
   name.

4. Watch the gem go out.  The `v*` tag runs `push_gem.yml`, which
   publishes through RubyGems.org's trusted publishing and then creates a
   GitHub release with generated notes.  Check once --
   `gh run list --workflow push_gem.yml --limit 1` -- and start one
   background wait on that run's conclusion:

       RUN=$(gh run list --workflow push_gem.yml --limit 1 --json databaseId --jq '.[0].databaseId')
       until gh run view $RUN --json status --jq .status | grep -q completed; do sleep 20; done
       gh run view $RUN --json conclusion --jq .conclusion

   Never poll in the foreground.  When it is green, confirm the version
   is up with `gem search -r -e mournmail`.  A red run means the tag is on
   the remote and the gem may not be on RubyGems.org; report the failed
   step's log (`gh run view $RUN --log-failed`), and leave the tag where
   it is -- the fix is a new release, not a moved tag.

5. Report: the version, the range the release covers
   (`v<previous>..v<new>`) with the commits that decided it, the
   workflow's conclusion once it arrives with
   https://rubygems.org/gems/mournmail, and the GitHub release
   (`gh release view v<N> --json url --jq .url`).  Nothing else needs
   updating for a release: the README carries no version number.
