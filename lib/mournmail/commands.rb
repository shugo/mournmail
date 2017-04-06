require "mail"

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
  s = Buffer.current.to_s.sub(/^--text follows this line--$/, "")
  m = Mail.new(s)
  m.delivery_method(:smtp, CONFIG[:mournmail_smtp_options])
  Buffer.current.modified = false
  kill_buffer(Buffer.current)
  Thread.start do
    begin
      m.deliver!
      next_tick do
        message("Mail sent.")
      end
    rescue Exception => e
      next_tick do
        raise e
      end
    end
  end
end
