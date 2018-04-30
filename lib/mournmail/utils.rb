# frozen_string_literal: true

require "mail"
require "net/imap"
require "time"
require "fileutils"
require "timeout"
require "groonga"

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
  define_variable :keep_alive_thread

  def self.background(skip_if_busy: false)
    if background_thread&.alive?
      return if skip_if_busy
    end
    self.background_thread = Utils.background {
      begin
        yield
      ensure
        self.background_thread = nil
      end
    }
  end

  def self.start_keep_alive_thread
    if keep_alive_thread
      raise EditorError, "Keep alive thread already running"
    end
    self.keep_alive_thread = Thread.start {
      loop do
        sleep(CONFIG[:mournmail_keep_alive_interval])
        background(skip_if_busy: true) do
          begin
            imap_connect do |imap|
              imap.noop
            end
          rescue => e
            message("Error in IMAP NOOP: #{e.class}: #{e.message}")
          end
        end
      end
    }
  end

  def self.stop_keep_alive_thread
    if keep_alive_thread
      keep_alive_thread&.kill
      self.keep_alive_thread = nil
    end
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

  def self.escape_binary(s)
    s.b.gsub(/[\x80-\xff]/n) { |c|
      "<%02X>" % c.ord
    }
  end

  def self.decode_eword(s)
    Mail::Encodings.decode_encode(s, :decode).
      encode(Encoding::UTF_8, replace: "?").gsub(/[\t\n]/, " ")
  rescue Encoding::CompatibilityError, Encoding::UndefinedConversionError
    escape_binary(s)
  end

  @imap = nil
  @imap_mutex = Mutex.new
  @mailboxes = []

  def self.imap_connect
    @imap_mutex.synchronize do
      if keep_alive_thread.nil?
        start_keep_alive_thread
      end
      if @imap.nil? || @imap.disconnected?
        Timeout.timeout(CONFIG[:mournmail_imap_connect_timeout]) do
          @imap = Net::IMAP.new(CONFIG[:mournmail_imap_host],
                                CONFIG[:mournmail_imap_options])
          @imap.authenticate(CONFIG[:mournmail_imap_options][:auth_type] ||
                             "PLAIN",
                             CONFIG[:mournmail_imap_options][:user_name],
                             CONFIG[:mournmail_imap_options][:password])
          @mailboxes = @imap.list("", "*").map { |mbox|
            Net::IMAP.decode_utf7(mbox.name)
          }
          if Mournmail.current_mailbox
            @imap.select(Mournmail.current_mailbox)
          end
        end
      end
      yield(@imap)
    end
  rescue IOError, Errno::ECONNRESET
    imap_disconnect
    raise
  end

  def self.imap_disconnect
    @imap_mutex.synchronize do
      stop_keep_alive_thread
      if @imap
        @imap.disconnect rescue nil
        @imap = nil
      end
    end
  end

  def self.fetch_summary(mailbox, all: false)
    imap_connect do |imap|
      imap.select(mailbox)
      if all
        summary = Mournmail::Summary.new(mailbox)
      else
        summary = Mournmail::Summary.load_or_new(mailbox)
      end
      first_uid = (summary.last_uid || 0) + 1
      data = imap.uid_fetch(first_uid..-1, ["UID", "ENVELOPE", "FLAGS"])
      summary.synchronize do
        data&.each do |i|
          uid = i.attr["UID"]
          next if summary[uid]
          env = i.attr["ENVELOPE"]
          flags = i.attr["FLAGS"]
          item = Mournmail::SummaryItem.new(uid, env.date, env.from,
                                            env.subject, flags)
          summary.add_item(item, env.message_id, env.in_reply_to)
        end
      end
      summary
    end
  end

  def self.mailbox_cache_path(mailbox)
    dir = CONFIG[:mournmail_directory]
    host = CONFIG[:mournmail_imap_host]
    File.expand_path("cache/#{host}/#{mailbox}", dir)
  end

  def self.read_mail(mailbox, uid)
    path = File.join(mailbox_cache_path(mailbox), uid.to_s)
    begin
      File.open(path) do |f|
        f.flock(File::LOCK_SH)
        [f.read, false]
      end
    rescue Errno::ENOENT
      imap_connect do |imap|
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
        [s, true]
      end
    end
  end

  def self.read_mailbox_name(prompt, **opts)
    f = ->(s) {
      complete_for_minibuffer(s, @mailboxes)
    }
    mailbox = read_from_minibuffer(prompt, completion_proc: f, **opts)
    Net::IMAP.encode_utf7(mailbox)
  end

  def self.force_utf8(s)
    s.force_encoding(Encoding::UTF_8).scrub("?")
  end

  def self.to_utf8(s, charset)
    if /\Autf-8\z/i =~ charset
      force_utf8(s)
    else
      begin
        s.encode(Encoding::UTF_8, charset, replace: "?")
      rescue Encoding::ConverterNotFoundError
        force_utf8(s)
      end
    end.gsub(/\r\n/, "\n")
  end

  @groonga_db = nil

  def self.open_groonga_db
    dir = CONFIG[:mournmail_directory]
    db_path = File.expand_path("groonga/messages.db", dir)
    if File.exist?(db_path)
      @groonga_db = Groonga::Database.open(db_path)
    else
      @groonga_db = create_groonga_db(db_path)
    end
  end

  def self.create_groonga_db(db_path)
    FileUtils.mkdir_p(File.dirname(db_path), mode: 0700)
    db = Groonga::Database.create(path: db_path)

    Groonga::Schema.create_table("Messages", :type => :hash) do |table|
      table.short_text("path")
      table.short_text("message_id")
      table.short_text("thread_id")
      table.time("date")
      table.short_text("subject")
      table.short_text("from")
      table.short_text("to")
      table.short_text("cc")
      table.short_text("list_id")
      table.text("body")
    end

    Groonga::Schema.create_table("Ids", :type => :hash) do |table|
      table.index("Messages.message_id")
      table.index("Messages.thread_id")
    end
    
    Groonga::Schema.create_table("Terms",
                                 type: :patricia_trie,
                                 normalizer: :NormalizerAuto,
                                 default_tokenizer: "TokenBigram") do |table|
      table.index("Messages.subject")
      table.index("Messages.from")
      table.index("Messages.to")
      table.index("Messages.cc")
      table.index("Messages.list_id")
      table.index("Messages.body")
    end

    db
  end

  def self.close_groonga_db
    if @groonga_db
      @groonga_db.close
    end
  end
end
