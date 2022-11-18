# Mournmail

Mournmail is a message user agent for
[Textbringer](https://github.com/shugo/textbringer).

## Installation

    $ gem install mournmail

## Configuration

```ruby
CONFIG[:mournmail_accounts] = {
  "example.com" => {
    from: "Shugo Maeda <shugo@example.com>",
    delivery_method: :smtp,
    delivery_options: {
      address: "smtp.example.com",
      port: 465,
      domain: Socket.gethostname,
      user_name: "shugo",
      password: File.read("/path/to/smtp_passwd").chomp,
      authentication: "login",
      tls: true,
      ca_file: "/path/to/ca.pem"
    },
    imap_host: "imap.example.com",
    imap_options: {
      auth_type: "PLAIN",
      user_name: "shugo",
      password: File.read("/path/to/imap_passwd").chomp,
      ssl: { ca_file: "/path/to/ca.pem" }
    },
    spam_mailbox: "spam",
    outbox_mailbox: "outbox",
    archive_mailbox_format: "archive/%Y",
    signature: <<~EOF
      -- 
      Shugo Maeda <shugo@example.com>
    EOF
  },
  "gmail.com" => {
    from: "Example <example@gmail.com>",
    delivery_method: :smtp,
    delivery_options: {
      address: "smtp.gmail.com",
      port: 587,
      domain: Socket.gethostname,
      user_name: "example@gmail.com",
      password: File.read("/path/to/gmail_passwd").chomp,
      authentication: "login",
      enable_starttls_auto: true
    },
    imap_host: "imap.gmail.com",
    imap_options: {
      auth_type: "PLAIN",
      user_name: "example@gmail.com",
      password: File.read(File.expand_path("~/.textbringer/gmail_passwd")).chomp,
      ssl: true
    },
    spam_mailbox: "[Gmail]/迷惑メール",
    archive_mailbox_format: false
  },
}
```

## Usage

Type `M-x mail` to send a mail.

Type `M-x mournmail` to visit INBOX.

## Key bindings

### Summary

|Key |Command |Description |
|---|---|---|
|s   |mournmail_summary_sync |Sync summary. With C-u sync all mails |
|SPC |summary_read_command |Read a mail |
|C-h |summary_scroll_down_command |Scroll down the current message |
|n   |summary_next_command |Display the next mail |
|w   |summary_write_command |Write a new mail |
|a   |summary_reply_command |Reply to the current message |
|A   |summary_reply_command |Reply to the current message |
|f   |summary_forward_command |Forward the current message |
|u   |summary_toggle_seen_command |Toggle Seen |
|$   |summary_toggle_flagged_command |Toggle Flagged |
|d   |summary_toggle_deleted_command |Toggle Deleted |
|x   |summary_toggle_mark_command |Toggle mark |
|* a |summary_mark_all_command |Mark all mails |
|* n |summary_unmark_all_command |Unmark all mails |
|* r |summary_mark_read_command |Mark read mails |
|* u |summary_mark_unread_command |Mark unread mails |
|* s |summary_mark_flagged_command |Mark flagged mails |
|* t |summary_mark_unflagged_command |Mark unflagged mails |
|y   |summary_archive_command |Archive mails. Archived mails will be deleted or refiled from the server, and only shown by summary_search_command |
|o   |summary_refile_command |Refile marked mails |
|!   |summary_refile_spam_command |Refile marked mails as spam |
|p   |summary_prefetch_command |Prefetch mails |
|X   |summary_expunge_command |Expunge deleted mails |
|v   |summary_view_source_command |View source of a mail |
|M   |summary_merge_partial_command |Merge marked message/partial |
|q   |mournmail_quit |Quit Mournmail |
|k   |previous_line |Move up |
|j   |next_line |Move down |
|m   |mournmail_visit_mailbox |Visit mailbox |
|S   |mournmail_visit_spam_mailbox |Visit spam mailbox |
|/   |summary_search_command |Search mails |
|t   |summary_show_thread_command |Show the thread of the current mail |
|@   |summary_change_account_command |Change the current account |

### Message

|Key |Command |Description |
|---|---|---|
|RET |message_open_link_or_part_command |Open link or MIME part |
|s   |message_save_part_command |Save the MIME part |
|TAB |message_next_link_or_part_command| Go to the next link or MIME part |

### Draft

|Key |Command |Description |
|---|---|---|
|C-c C-c     |draft_send_command |Send a mail |
|C-c C-k     |draft_kill_command |Kill the draft buffer |
|C-c C-x TAB |draft_attach_file_command |Attach a file |
|C-c C-x v   |draft_pgp_sign_command |PGP sign |
|C-c C-x e   |draft_pgp_encrypt_command |PGP encrypt |
|C-c TAB     |insert_signature_command |Insert signature |
|C-c @       |draft_change_account_command |Change account |
|TAB         |draft_complete_or_insert_tab_command |Complete a mail address or insert a tab |

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/shugo/mournmail.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

