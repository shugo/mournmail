# frozen_string_literal: true

module Textbringer
  CONFIG[:mournmail_directory] = File.expand_path("~/.mournmail")
  CONFIG[:mournmail_from] = ""
  CONFIG[:mournmail_delivery_method] = :smtp
  CONFIG[:mournmail_delivery_options] = {}
  CONFIG[:mournmail_charset] = "utf-8"
  CONFIG[:mournmail_save_directory] = "/tmp"
  CONFIG[:mournmail_display_header_fields] = [
    "Subject",
    "Date",
    "From",
    "To",
    "Cc",
    "Reply-To",
    "User-Agent",
    "X-Mailer",
    "Content-Type"
  ]
  CONFIG[:mournmail_imap_connect_timeout] = 10
  CONFIG[:mournmail_keep_alive_interval] = 60
  CONFIG[:mournmail_file_open_comamnd] = "xdg-open"
  CONFIG[:mournmail_link_open_comamnd] = "xdg-open"
  CONFIG[:mournmail_outbox] = nil
  CONFIG[:mournmail_addresses_path] = File.expand_path("~/.addresses")
end
