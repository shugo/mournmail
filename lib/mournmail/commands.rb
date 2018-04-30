# frozen_string_literal: true

define_command(:mournmail, doc: "Start mournmail.") do
  Mournmail.open_groonga_db
  mournmail_visit_mailbox("INBOX")
end

define_command(:mournmail_visit_mailbox, doc: "Start mournmail.") do
  |mailbox = Mournmail.read_mailbox_name("Visit mailbox: ", default: "INBOX")|
  mournmail_summary_sync(mailbox)
end

define_command(:mournmail_summary_sync, doc: "Sync summary.") do
  |mailbox = (Mournmail.current_mailbox || "INBOX"),
    all = current_prefix_arg|
  message("Syncing #{mailbox} in background...")
  Mournmail.background do
    summary = Mournmail.fetch_summary(mailbox, all: all)
    summary_text = summary.to_s
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
        buffer.beginning_of_buffer
        buffer.re_search_forward(/^\d+ u/)
      rescue SearchError
        buffer.end_of_buffer
        buffer.re_search_backward(/^\d+ /, raise_error: false)
      end
      summary_read_command
    end
  end
end

define_command(:mournmail_quit, doc: "Quit mournmail.") do
  th = Mournmail.background_thread
  if th
    return unless yes_or_no?("A background process is running. Kill it?")
    th.kill
  end
  delete_other_windows
  if buffer = Buffer["*summary*"]
    kill_buffer(buffer)
  end
  if buffer = Buffer["*message*"]
    kill_buffer(buffer)
  end
  Mournmail.background do
    Mournmail.imap_disconnect
  end
  Mournmail.current_mailbox = nil
  Mournmail.current_summary = nil
  Mournmail.current_mail = nil
  Mournmail.current_uid = nil
  Mournmail.close_groonga_db
end

define_command(:mail, doc: "Write a new mail.") do
  |run_hooks: true|
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
  if run_hooks
    run_hooks(:mournmail_draft_setup_hook)
  end
end

def ljust(s, n)
  width = 0
  str = String.new
  s.gsub(/\t/, " ").each_char do |c|
    w = Buffer.display_width(c)
    width += w
    if width > n
      width -= w
      break
    end
    str.concat(c)
    break if width == n
  end
  str + " " * (n - width)
end

define_command(:mm_search) do
  |query = read_from_minibuffer("Search mail: ")|
  words = query.split
  if words.empty?
    raise EditorError, "No word given"
  end
  Mournmail.background do
    messages = Groonga["Messages"].select { |m|
      words.inject(nil) { |e, word|
        if e.nil?
          m.subject =~ word 
        else
          e & (m.subject =~ word)
        end
      } | words.inject(nil) { |e, word|
        if e.nil?
          m.body =~ word 
        else
          e & (m.body =~ word)
        end
      }
    }.sort([key: "date", order: "descending"]).take(100)
    summary_text = messages.map { |m|
      format("%s [ %s ] %s\n",
             m.date.strftime("%m/%d %H:%M"),
             ljust(m.from, 16),
             ljust(m.subject, 45))
    }.join
    next_tick do
      buffer = Buffer.find_or_new("*search result*", undo_limit: 0,
                                  read_only: true)
      buffer.apply_mode(Mournmail::SearchResultMode)
      buffer.read_only_edit do
        buffer.clear
        buffer.insert(summary_text)
        buffer.beginning_of_buffer
      end
      buffer[:messages] = messages
      switch_to_buffer(buffer)
    end
  end
end
