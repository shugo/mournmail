# frozen_string_literal: true

require "mail"
require "mail-iso-2022-jp"
require "net/imap"
require "time"
require "fileutils"

module Mournmail
  def self.define_variable(name, value = nil)
    instance_variable_set("@" + name.to_s, value)
    singleton_class.send(:attr_accessor, name)
  end

  define_variable :current_mailbox
  define_variable :current_summary
  define_variable :current_uid
  define_variable :current_mail
  define_variable :background_thread

  def self.background
    if background_thread&.alive?
      raise EditorError, "Background thread already running"
    end
    self.background_thread = Utils.background {
      begin
        yield
      ensure
        self.background_thread = nil
      end
    }
  end

  def self.message_window
    if Window.list.size == 1
      split_window
      shrink_window(Window.current.lines - 8)
    end
    windows = Window.list
    i = (windows.index(Window.current) + 1) % windows.size
    windows[i]
  end

  class Summary
    attr_reader :items, :last_uid

    def self.cache_path(mailbox)
      File.expand_path("cache/#{mailbox}/.summary",
                       CONFIG[:mournmail_directory])
    end

    def self.load(mailbox)
      File.open(cache_path(mailbox)) { |f|
        f.flock(File::LOCK_SH)
        Marshal.load(f)
      }
    end

    def self.load_or_new(mailbox)
      load(mailbox)
    rescue Errno::ENOENT
      new(mailbox)
    end

    def initialize(mailbox)
      @mailbox = mailbox
      @items = []
      @message_id_table = {}
      @uid_table = {}
      @last_uid = nil
    end

    def add_item(item, message_id, in_reply_to)
      parent = @message_id_table[in_reply_to]
      if parent
        parent.add_reply(item)
      else
        @items.push(item)
      end
      if message_id
        @message_id_table[message_id] = item
      end
      @uid_table[item.uid] = item
      @last_uid = item.uid
    end

    def [](uid)
      @uid_table[uid]
    end

    def save
      path = Summary.cache_path(@mailbox)
      FileUtils.mkdir_p(File.dirname(path))
      File.open(Summary.cache_path(@mailbox), "w") do |f|
        f.flock(File::LOCK_EX)
        Marshal.dump(self, f)
      end
    end
  end
  
  class SummaryItem
    attr_reader :uid, :date, :from, :subject, :flags
    attr_reader :replies
    
    def initialize(uid, date, from, subject, flags)
      @uid = uid
      @date = date
      @from = from
      @subject = subject
      @flags = flags
      @line = nil
      @replies = []
    end
    
    def add_reply(reply)
      @replies << reply
    end
    
    def to_s(limit = 78, from_limit = 16, level = 0)
      @line ||= format_line(limit, from_limit, level)
      return @line if @replies.empty?
      s = @line.dup
      child_level = level + 1
      @replies.each do |reply|
        s << reply.to_s(limit, from_limit, child_level)
      end
      s
    end

    def set_flag(flag)
      @flags.push(flag)
      @line = nil
    end
    
    private

    def format_line(limit = 78, from_limit = 16, level = 0)
      space = "  " * (level < 8 ? level : 8)
      s = String.new
      s << format("%s %s%s %s[ %s ] ",
                  @uid, format_flags(@flags), format_date(@date), space,
                  ljust(format_from(@from), from_limit))
      s << ljust(decode_eword(@subject.to_s), limit - Buffer.display_width(s))
      s << "\n"
      s
    end
    
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

    def format_flags(flags)
      if flags.include?(:Flagged)
        "$"
      elsif !flags.include?(:Seen)
        "u"
      else
        " "
      end
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
end

define_command(:mournmail, doc: "Start mournmail.") do
  mournmail_visit_mailbox("INBOX")
end

def mournmail_imap_connect
  imap = Net::IMAP.new(CONFIG[:mournmail_imap_host],
                       CONFIG[:mournmail_imap_options])
  begin
    imap.authenticate(CONFIG[:mournmail_imap_options][:auth_type] || "PLAIN",
                      CONFIG[:mournmail_imap_options][:user_name],
                      CONFIG[:mournmail_imap_options][:password])
    yield(imap)
  ensure
    imap.disconnect
  end
end

def mournmail_fetch_summary(mailbox)
  mournmail_imap_connect do |imap|
    imap.select(mailbox)
    summary = Mournmail::Summary.load_or_new(mailbox)
    first_uid = (summary.last_uid || 0) + 1
    if first_uid != imap.responses["UIDNEXT"]&.last
      data = imap.uid_fetch(first_uid..-1, ["UID", "ENVELOPE", "FLAGS"])
      data.each do |i|
        uid = i.attr["UID"]
        env = i.attr["ENVELOPE"]
        flags = i.attr["FLAGS"]
        item = Mournmail::SummaryItem.new(uid, env.date, env.from, env.subject,
                                          flags)
        summary.add_item(item, env.message_id, env.in_reply_to)
      end
    end
    summary
  end
end

define_command(:mournmail_visit_mailbox, doc: "Start mournmail.") do
  |mailbox = read_from_minibuffer("Visit mailbox: ", default: "INBOX")|
  message("Visiting #{mailbox} in background...")
  Mournmail.background do
    summary = mournmail_fetch_summary(mailbox)
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
      message("Visited #{mailbox}")
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

def mournmail_read_mail(mailbox, uid)
  path = File.expand_path("cache/#{mailbox}/#{uid}",
                          CONFIG[:mournmail_directory])
  begin
    File.open(path) do |f|
      f.flock(File::LOCK_SH)
      f.read
    end
  rescue Errno::ENOENT
    mournmail_imap_connect do |imap|
      imap.select(mailbox)
      data = imap.uid_fetch(uid, "BODY[]")
      if data.empty?
        raise EditorError, "No such mail: #{uid}"
      end
      s = data[0].attr["BODY[]"]
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, "w") do |f|
        f.flock(File::LOCK_EX)
        f.write(s)
      end
      s
    end
  end
end

define_command(:mournmail_summary_read, doc: "Read a mail.") do
  summary_buffer = Buffer.current
  begin
    uid = summary_buffer.save_excursion {
      summary_buffer.beginning_of_line
      return if !summary_buffer.looking_at?(/\d+/)
      match_string(0).to_i
    }
    if uid == Mournmail.current_uid
      window = Mournmail.message_window
      if window.buffer.name == "*message*"
        old_window = Window.current
        begin
          Window.current = window
          scroll_up
          return
        ensure
          Window.current = old_window
        end
      end
    end
  rescue RangeError # may be raised by scroll_up
    summary_buffer.end_of_line
    if summary_buffer.end_of_buffer?
      raise EditorError, "No more mail"
    end
    summary_buffer.forward_line
    retry
  end
  Mournmail.background do
    mailbox = Mournmail.current_mailbox
    mail = Mail.new(mournmail_read_mail(mailbox, uid))
    body = if mail.multipart?
      mail.text_part&.decoded
    else
      mail.body.decoded.encode(Encoding::UTF_8, mail.charset,
                               replace: "?")
    end.gsub(/\r\n/, "\n")
    message = <<~EOF
        Subject: #{mail.subject}
        Date: #{mail.date}
        From: #{mail["from"]}
        To: #{mail["to"]}

        #{body}
      EOF
    next_tick do
      message_buffer = Buffer.find_or_new("*message*",
                                          undo_limit: 0, read_only: true)
      message_buffer.apply_mode(Mournmail::MessageMode)
      message_buffer.read_only_edit do
        message_buffer.clear
        message_buffer.insert(message)
        message_buffer.beginning_of_buffer
      end
      window = Mournmail.message_window
      window.buffer = message_buffer
      summary_item = Mournmail.current_summary[uid]
      if summary_item && !summary_item.flags.include?(:Seen)
        summary_item.set_flag(:Seen)
        Mournmail.current_summary.save
        summary_buffer.read_only_edit do
          summary_buffer.save_excursion do
            summary_buffer.beginning_of_line
            if summary_buffer.looking_at?(/^(\d+) u/)
              summary_buffer.replace_match('\1  ')
            end
          end
        end
      end
      Mournmail.current_uid = uid
      Mournmail.current_mail = mail
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
