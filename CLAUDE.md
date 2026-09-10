# Guidelines

## Repository

- origin = shugo/mournmail.  Work happens on `main`; a change that wants
  review goes on a branch of its own, and Shugo opens the pull request
  himself -- do not open one unless asked (the `pr` skill is that ask).
- Mournmail is a Textbringer plugin, not a standalone library.  The files
  under `lib/mournmail/` use Textbringer's globals -- `CONFIG`,
  `define_command`, `Buffer`, `insert` -- so `require "mournmail"` works
  only after what Textbringer's plugin loader has already done:

      require "textbringer"; include Textbringer; include Textbringer::Commands

  `bin/console` does not do this and fails as it stands.
- Buffers, windows and the minibuffer belong to the foreground thread.
  IMAP and other network work runs in `Mournmail.background`; anything
  that reads or writes a buffer, the selected line (`selected_uid`) or a
  window is done before the background block starts or inside
  `foreground { }` in it.  Commits 70a8133 and 7e48bd4 are what getting
  this wrong looks like.
- rroonga needs Groonga.  CI installs `libgroonga-dev` from
  packages.groonga.org; a locally built rroonga whose `groonga.so` fails
  with `libgroonga-llama.so.0` missing needs `LD_LIBRARY_PATH` pointing at
  the gem's `vendor/local/lib`.
- Do not change the CI workflows (`.github/workflows/`) to run work in
  progress.  `test.yml` runs on pushes to `main` and on pull requests; to
  reach CI for a branch, ask first, then open a draft pull request.
- Keep scratch files out of the working tree; the session scratchpad is
  for them.  Stage files by name -- `git add -A` is never the right
  command here.

## Commits

- English, imperative mood, ASCII.  The body carries the rationale, the
  rejected alternatives and anything measured; 7e48bd4 shows the register.
- End the message with a single trailer naming the model actually in use,
  e.g. `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`, and
  nothing after it -- no `Claude-Session` line, no session URLs, no
  "Generated with" lines, even when the session's own attribution guidance
  asks for them.  Pull request descriptions keep the same restraint.
- If the message contains backticks or other shell metacharacters, write
  it to a file and use `git commit -F <file>`; passing it with `-m` can
  silently lose words.
- Before any force-push, verify the remote SHA with `git ls-remote` and use
  `--force-with-lease`.
- Do not commit or push until asked; finish the change, run the
  verification, and report.  The `push`, `pr` and `release` skills are the
  ask.

## Code

- Two-space indentation, LF line endings, lines within 80 columns.
- A comment must say something the code cannot: a constraint, or the
  reason a thing is the way it is.  Do not document what is absent.
  Rationale, rejected alternatives and history go in the commit message.
- CI runs with `--enable-frozen-string-literal`, so a string literal that
  is appended to later is written `+""` or duplicated first, as
  `Summary#format_line` and the encoded-word patch do.
- Header fields inserted into a draft buffer go through
  `Mournmail.fold_header_field`, and `draft_send` unfolds them before the
  mail gem folds them again with CRLF (RFC 5322 2.2.3).

## Tests

```sh
bundle exec rake test                        # test-unit, test/test_*.rb
ruby -Ilib:test test/test_header_folding.rb  # one file
```

- A test file requires only the file under test and the gems it needs,
  not `mournmail` as a whole, which would need Textbringer's globals and a
  working Groonga.  A helper that can be pure -- header folding is one --
  lives in its own file under `lib/mournmail/`, required from
  `lib/mournmail.rb`, so that it can be tested this way.
- `.github/workflows/test.yml` runs the suite on Ubuntu with Ruby 4.0.

## Releasing

```sh
bundle exec rake bump
```

Versions are single integers since v2.  `rake bump` checks out `main`,
pulls, adds one to `VERSION` in `lib/mournmail/version.rb`, commits that
file as `Bump version to <N>`, pushes, and pushes the tag `v<N>`.  The tag
runs `.github/workflows/push_gem.yml`, which publishes through RubyGems.org's
trusted publishing and creates a GitHub release with generated notes.
Do not run `bundle exec rake release`: it pushes the gem from the local
machine too, and the two pushes conflict, which is how the v3 workflow run
failed.  The `release` skill wraps the checks around this.
