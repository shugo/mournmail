# frozen_string_literal: true

require "mail"
require "mail-iso-2022-jp"
require "net/imap"
require "time"
require "fileutils"

module Mournmail
  begin
    require "mail-gpg"
    HAVE_MAIL_GPG = true
  rescue LoadError
    HAVE_MAIL_GPG = false
  end

  def self.define_variable(name, value = nil)
    var_name = "@" + name.to_s
    if !instance_variable_defined?(var_name)
      instance_variable_set(var_name, value)
    end
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

  def self.back_to_summary
    summary_window = Window.list.find { |window|
      window.buffer.name == "*summary*"
    }
    if summary_window
      Window.current = summary_window
    end
  end

  def self.decode_eword(s)
    Mail::Encodings.decode_encode(s, :decode).
      encode(Encoding::UTF_8).gsub(/[\t\n]/, " ")
  rescue Encoding::CompatibilityError, Encoding::UndefinedConversionError
    s.b.gsub(/[\x80-\xff]/n) { |c|
      "<%02X>" % c.ord
    }
  end
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

def mournmail_fetch_summary(mailbox, all: false)
  mournmail_imap_connect do |imap|
    imap.select(mailbox)
    if all
      summary = Mournmail::Summary.new(mailbox)
    else
      summary = Mournmail::Summary.load_or_new(mailbox)
    end
    first_uid = (summary.last_uid || 0) + 1
    data = imap.uid_fetch(first_uid..-1, ["UID", "ENVELOPE", "FLAGS"])
    data.each do |i|
      uid = i.attr["UID"]
      next if summary[uid]
      env = i.attr["ENVELOPE"]
      flags = i.attr["FLAGS"]
      item = Mournmail::SummaryItem.new(uid, env.date, env.from, env.subject,
                                        flags)
      summary.add_item(item, env.message_id, env.in_reply_to)
    end
    summary
  end
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
      File.open(path, "w", 0600) do |f|
        f.flock(File::LOCK_EX)
        f.write(s)
      end
      s
    end
  end
end
