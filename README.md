# Mournmail

Mournmail is a message user agent for
[Textbringer](https://github.com/shugo/textbringer).

## Installation

    $ gem install mournmail

## Configuration

```ruby
# The default value of From:
CONFIG[:mournmail_from] = "Shugo Maeda <shugo@example.com>"
# The default charset
CONFIG[:mournmail_charset] = "iso-2022-jp"
# The delivery method for Mail#delivery_method
CONFIG[:mournmail_delivery_method] = :smtp
# The options for Mail#delivery_method
CONFIG[:mournmail_delivery_options] = {
  :address => "smtp.example.com",
  :port => 465,
  :domain => Socket.gethostname,
  :user_name => "shugo",
  :password => File.read("/path/to/smtp_passwd").chomp,
  :authentication => "login",
  :tls => true,
  :ca_file => "/path/to/cacert.pem"
}
# The host for Net::IMAP#new
CONFIG[:mournmail_imap_host] = "imap.example.com"
# The options for Net::IMAP.new and
# Net::IMAP#authenticate (auth_type, user_name, and password)
CONFIG[:mournmail_imap_options] = {
  ssl: {
    :ca_file => File.expand_path("/path/to/cacert.pem")
  },
  auth_type: "PLAIN",
  user_name: "shugo",
  password: File.read("/path/to/imap_passwd").chomp
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

