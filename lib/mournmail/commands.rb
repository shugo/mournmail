# frozen_string_literal: true

using Mournmail::MessageRendering

define_command(:mournmail, doc: "Start mournmail.") do
  mournmail_visit_mailbox("INBOX")
end

define_command(:mournmail_visit_mailbox, doc: "Start mournmail.") do
  |mailbox = read_from_minibuffer("Visit mailbox: ", default: "INBOX")|
  mournmail_summary_sync(mailbox)
end

define_command(:mournmail_summary_sync, doc: "Sync summary.") do
  |mailbox = (Mournmail.current_mailbox || "INBOX"),
    all = current_prefix_arg|
  message("Syncing #{mailbox} in background...")
  Mournmail.background do
    summary = mournmail_fetch_summary(mailbox, all: all)
    summary_text = String.new
    summary.items.each do |item|
      summary_text << item.to_s
    end
    summary.save
    next_tick do
      buffer = Buffer.find_or_new("*summary*", undo_limit: 0,
                                  read_only: true)
      buffer.apply_mode(Mournmail::SummaryMode)
      buffer.read_only_edit do
        buffer.clear
        buffer.insert(summary_text)
      end
      switch_to_buffer(buffer)
      Mournmail.current_mailbox = mailbox
      Mournmail.current_summary = summary
      Mournmail.current_mail = nil
      Mournmail.current_uid = nil
      message("Syncing #{mailbox} in background... Done")
      begin
        beginning_of_buffer
        re_search_forward(/^\d+ u/)
      rescue SearchError
        end_of_buffer
        re_search_backward(/^\d+ /)
      end
      summary_read_command
    end
  end
end

define_command(:mournmail_quit, doc: "Quit mournmail.") do
  delete_other_windows
  if buffer = Buffer["*summary*"]
    kill_buffer(buffer)
  end
  if buffer = Buffer["*message*"]
    kill_buffer(buffer)
  end
  Mournmail.current_mailbox = nil
  Mournmail.current_summary = nil
  Mournmail.current_mail = nil
  Mournmail.current_uid = nil
end

define_command(:mournmail_message_save_part, doc: "Save the current part.") do
  buffer = Buffer.current
  buffer.save_excursion do
    buffer.beginning_of_line
    if buffer.looking_at?(/\[([0-9.]+) .*\]/)
      index = match_string(1)
      indices = index.split(".").map(&:to_i)
      part = Mournmail.current_mail.dig_part(*indices)
      default_name = part["content-disposition"]&.parameters&.[]("filename") ||
        part["content-type"]&.parameters&.[]("name") ||
        Mournmail.current_uid.to_s + "-" + index
      decoded_name = Mail::Encodings.decode_encode(default_name, :decode)
      if /\A([A-Za-z0-9_\-]+)'(?:[A-Za-z0-9_\-])*'(.*)/ =~ decoded_name
        decoded_name = $2.encode("utf-8", $1)
      end
      default_path = File.expand_path(decoded_name,
                                      CONFIG[:mournmail_save_directory])
      path = read_file_name("Save: ", default: default_path)
      if !File.exist?(path) || yes_or_no?("File exists; overwrite?")
        File.write(path, part.decoded)
      end
    end
  end
end

define_command(:mail, doc: "Write a new mail.") do
  buffer = Buffer.new_buffer("*draft*")
  switch_to_buffer(buffer)
  draft_mode
  insert <<~EOF
    From: #{CONFIG[:mournmail_from]}
    To: 
    Subject: 
    User-Agent: Mournmail/#{Mournmail::VERSION} Textbringer/#{Textbringer::VERSION} Ruby/#{RUBY_VERSION}
    --text follows this line--
  EOF
  re_search_backward(/^To:/)
  end_of_line
end

define_command(:mournmail_draft_send,
               doc: "Send a mail and exit from mail buffer.") do
  s = Buffer.current.to_s
  charset = CONFIG[:mournmail_charset]
  begin
    s.encode(charset)
  rescue Encoding::UndefinedConversionError
    charset = "utf-8"
  end
  m = Mail.new(charset: charset)
  header, body = s.split(/^--text follows this line--\n/, 2)
  attached_files = []
  attached_messages = []
  header.scan(/^([!-9;-~]+):[ \t]*(.*(?:\n[ \t].*)*)\n/) do |name, val|
    case name
    when "Attached-File"
      attached_files.push(val.strip)
    when "Attached-Message"
      attached_messages.push(val.strip)
    else
      m[name] = val
    end
  end
  if body.empty?
    return if !yes_or_no?("Body is empty.  Really send?")
  else
    if attached_files.empty? && attached_messages.empty?
      m.body = body
    else
      part = Mail::Part.new(content_type: "text/plain", body: body)
      part.charset = charset
      m.body << part
    end
  end
  attached_files.each do |file|
    m.add_file(file)
  end
  m.delivery_method(CONFIG[:mournmail_delivery_method],
                    CONFIG[:mournmail_delivery_options])
  buffer = Buffer.current
  bury_buffer(buffer)
  background do
    begin
      if !attached_messages.empty?
        attached_messages.each do |attached_message|
          mailbox, uid = attached_message.strip.split("/")
          s = mournmail_read_mail(mailbox, uid.to_i)
          part = Mail::Part.new(content_type: "message/rfc822", body: s)
          m.body << part
        end
      end
      m.deliver!
      next_tick do
        kill_buffer(buffer, force: true)
        Mournmail.back_to_summary
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

define_command(:mournmail_draft_kill, doc: "Kill the draft buffer.") do
  if yes_or_no?("Kill current draft?")
    kill_buffer(Buffer.current, force: true)
    Mournmail.back_to_summary
  end
end

define_command(:mournmail_draft_attach_file, doc: "Attach a file.") do
  |file_name = read_file_name("Attach file: ")|
  buffer = Buffer.current
  buffer.save_excursion do
    buffer.beginning_of_buffer
    buffer.re_search_forward(/^--text follows this line--$/)
    buffer.beginning_of_line
    buffer.insert("Attached-File: #{file_name}\n")
  end
end
