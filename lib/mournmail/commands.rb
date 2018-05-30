# frozen_string_literal: true

define_command(:mournmail, doc: "Start mournmail.") do
  Mournmail.open_groonga_db
  mournmail_visit_mailbox("INBOX")
end

define_command(:mournmail_visit_mailbox, doc: "Visit mailbox") do
  |mailbox = Mournmail.read_mailbox_name("Visit mailbox: ", default: "INBOX")|
  summary = Mournmail::Summary.load_or_new(mailbox)
  next_tick do
    Mournmail.show_summary(summary)
  end
end

define_command(:mournmail_summary_sync, doc: "Sync summary.") do
  |mailbox = (Mournmail.current_mailbox || "INBOX"),
    all = current_prefix_arg|
  message("Syncing #{mailbox} in background...")
  Mournmail.background do
    summary = Mournmail.fetch_summary(mailbox, all: all)
    summary.save
    next_tick do
      Mournmail.show_summary(summary)
      message("Syncing #{mailbox} in background... Done")
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
  conf = Mournmail.account_config
  insert <<~EOF
    From: #{conf[:from]}
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
