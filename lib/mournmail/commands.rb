# frozen_string_literal: true

require "mail"
require "mail-iso-2022-jp"

define_command(:mail, doc: "Write a new mail.") do
  buffer = Buffer.new_buffer("*mail*")
  switch_to_buffer(buffer)
  mail_mode
  insert <<~EOF
    From: #{CONFIG[:mournmail_from]}
    To: 
    Subject: 
    User-Agent: Mournmail/#{Mournmail::VERSION} Textbringer/#{Textbringer::VERSION}
    --text follows this line--
  EOF
  re_search_backward(/^To:/)
  end_of_line
end

define_command(:mail_send, doc: "Send a mail and exit from mail buffer.") do
  s = Buffer.current.to_s
  charset = CONFIG[:mournmail_charset]
  begin
    s.encode(charset)
  rescue Encoding::UndefinedConversionError
    charset = "utf-8"
  end
  header, body = s.split(/^--text follows this line--\n/)
  m = Mail.new(charset: charset)
  header.scan(/^([!-9;-~]+):[ \t]*(.*(?:\n[ \t].*)*)\n/) do |name, val|
    m[name] = val
  end
  m.body = body
  m.delivery_method(CONFIG[:mournmail_delivery_method],
                    CONFIG[:mournmail_delivery_options])
  buffer = Buffer.current
  bury_buffer(buffer)
  background do
    begin
      m.deliver!
      next_tick do
        kill_buffer(buffer, force: true)
        message("Mail sent.")
      end
    rescue Exception
      next_tick do
        switch_to_buffer(buffer)
      end
      raise
    end
  end
end

define_command(:mail_kill, doc: "Kill mail buffer.") do
  if yes_or_no?("Kill current mail?")
    kill_buffer(Buffer.current, force: true)
  end
end
