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

## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/shugo/mournmail.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

