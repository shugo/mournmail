# frozen_string_literal: true

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
    summary = Mournmail.fetch_summary(mailbox, all: all)
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
  Mournmail.imap_disconnect
  Mournmail.current_mailbox = nil
  Mournmail.current_summary = nil
  Mournmail.current_mail = nil
  Mournmail.current_uid = nil
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
