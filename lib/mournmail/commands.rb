# frozen_string_literal: true

require "mail"
require "mail-iso-2022-jp"
require "net/imap"
require "time"

class SummaryItem
  attr_reader :uid, :date, :from, :subject
  attr_reader :replies

  def initialize(uid, date, from, subject)
    @uid = uid
    @date = date
    @from = from
    @subject = subject
    @replies = []
  end

  def add_reply(reply)
    @replies << reply
  end

  def to_s(limit = 78, from_limit = 16, level = 0)
    space = "  " * (level < 8 ? level : 8)
    s = String.new
    s << format("%s  %s%s [ %s ] ",
                @uid, space, format_date(@date),
                ljust(format_from(@from), from_limit))
    s << ljust(decode_eword(@subject.to_s), limit - Buffer.display_width(s))
    s << "\n"
    child_level = level + 1
    @replies.each do |reply|
      begin
        s << reply.to_s(limit, from_limit, child_level)
      rescue TypeError
        raise "s=#{s.inspect}, reply=#{reply.inspect}, limit=#{limit.inspect}"
      end
    end
    s
  end

  private

  def ljust(s, n)
    width = 0
    str = String.new
    s.each_char do |c|
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

  def format_date(date)
    (Time.parse(date) rescue Time.at(0)).strftime("%m/%d %H:%M")
  end

  def format_from(from)
    addr = from[0]
    if addr&.name
      "#{decode_eword(addr.name)} <#{addr.mailbox}@#{addr.host}>"
    elsif addr&.mailbox
      "#{addr.mailbox}@#{addr.host}"
    else
      "Unknown sender"
    end
  end 

  def decode_eword(s)
    Mail::Encodings.decode_encode(s, :decode).
      encode(Encoding::UTF_8).tr("\t", " ")
  rescue Encoding::CompatibilityError, Encoding::UndefinedConversionError
    s.b.gsub(/[\x80-\xff]/n) { |c|
      "<%02X>" % c.ord
    }
  end
end

define_command(:mournmail, doc: "Start mournmail.") do
  mournmail_visit_mailbox("INBOX")
end

def mournmail_background
  if $mournmail_background_thread
    raise EditorError, "Background thread already running"
  end
  $mournmail_background_thread = background {
    begin
      yield
    ensure
      $mournmail_background_thread = nil
    end
  }
end

def mournmail_fetch_summary(mailbox)
  imap = Net::IMAP.new(CONFIG[:mournmail_imap_host],
                       CONFIG[:mournmail_imap_options])
  begin
    imap.authenticate(CONFIG[:mournmail_imap_options][:auth_type] || "PLAIN",
                      CONFIG[:mournmail_imap_options][:user_name],
                      CONFIG[:mournmail_imap_options][:password])
    imap.select(mailbox)
    data = imap.fetch(1..-1, ["UID", "ENVELOPE"])
    message_id_table = {}
    summary_items = []
    data.each do |i|
      uid = i.attr["UID"]
      env = i.attr["ENVELOPE"]
      item = SummaryItem.new(uid, env.date, env.from, env.subject)
      parent = message_id_table[env.in_reply_to]
      if parent
        parent.add_reply(item)
      else
        summary_items.push(item)
      end
      if env.message_id
        message_id_table[env.message_id] = item
      end
    end
    summary_items
  ensure
    imap.disconnect
  end
end

define_command(:mournmail_visit_mailbox, doc: "Start mournmail.") do
  |mailbox = read_from_minibuffer("Visit mailbox: ", default: "INBOX")|
  message("Visit #{mailbox} in background...")
  mournmail_background do
    # TODO: Cache items.
    summary_items = mournmail_fetch_summary(mailbox)
    next_tick do
      buffer = Buffer.find_or_new("*summary*", undo_limit: 0,
                                  read_only: true)
      buffer.read_only_edit do
        buffer.clear
        summary_items.each do |item|
          buffer.insert(item.to_s)
        end
      end
      switch_to_buffer(buffer)
      message("Visited #{mailbox}")
    end
  end
end

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
