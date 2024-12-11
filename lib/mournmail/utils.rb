require "mail"
require "net/imap"
require "time"
require "tempfile"
require "fileutils"
require "timeout"
require "digest"
require "nkf"
require "groonga"
require 'google/api_client/client_secrets'
require 'google/api_client/auth/storage'
require 'google/api_client/auth/storages/file_store'
require 'launchy'
require "socket"

if defined?(Net::SMTP::Authenticator)
  class Net::SMTP
    class AuthXOAuth2 < Net::SMTP::Authenticator
      auth_type :xoauth2

      def auth(user, secret)
        s = Net::IMAP::XOauth2Authenticator.new(user, secret).process("")
        finish('AUTH XOAUTH2 ' + base64_encode(s))
      end
    end
  end
else    
  class Net::SMTP
    def auth_xoauth2(user, secret)
      check_auth_args user, secret
      res = critical {
        s = Net::IMAP::XOauth2Authenticator.new(user, secret).process("")
        get_response('AUTH XOAUTH2 ' + base64_encode(s))
      }
      check_auth_response res
      res
    end
  end
end

module Mournmail
  begin
    require "mail-gpg"
    HAVE_MAIL_GPG = true
  rescue LoadError
    HAVE_MAIL_GPG = false
  end

  def self.define_variable(name, initial_value: nil, attr: nil)
    var_name = "@" + name.to_s
    if !instance_variable_defined?(var_name)
      instance_variable_set(var_name, initial_value)
    end
    case attr
    when :accessor
      singleton_class.send(:attr_accessor, name)
    when :reader
      singleton_class.send(:attr_reader, name)
    when :writer
      singleton_class.send(:attr_writer, name)
    end
  end

  define_variable :current_mailbox, attr: :accessor
  define_variable :current_summary, attr: :accessor
  define_variable :current_uid, attr: :accessor
  define_variable :current_mail, attr: :accessor
  define_variable :background_thread, attr: :accessor
  define_variable :background_thread_mutex, initial_value: Mutex.new
  define_variable :keep_alive_thread, attr: :accessor
  define_variable :keep_alive_thread_mutex, initial_value: Mutex.new
  define_variable :imap
  define_variable :imap_mutex, initial_value: Mutex.new
  define_variable :mailboxes, initial_value: []
  define_variable :current_account
  define_variable :account_config
  define_variable :groonga_db

  def self.background(skip_if_busy: false)
    @background_thread_mutex.synchronize do
      if background_thread&.alive?
        if skip_if_busy
          return
        else
          raise EditorError, "Another background thread is running"
        end
      end
      self.background_thread = Utils.background {
        begin
          yield
        ensure
          self.background_thread = nil
        end
      }
    end
  end

  def self.start_keep_alive_thread
    @keep_alive_thread_mutex.synchronize do
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
  end

  def self.stop_keep_alive_thread
    @keep_alive_thread_mutex.synchronize do
      if keep_alive_thread
        keep_alive_thread&.kill
        self.keep_alive_thread = nil
      end
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

  def self.current_account
    init_current_account
    @current_account
  end

  def self.account_config
    init_current_account
    @account_config
  end

  def self.init_current_account
    if @current_account.nil?
      @current_account, @account_config = CONFIG[:mournmail_accounts].first
    end
  end

  def self.current_account=(name)
    unless CONFIG[:mournmail_accounts].key?(name)
      raise ArgumentError, "No such account: #{name}"
    end
    @current_account = name
    @account_config = CONFIG[:mournmail_accounts][name]
  end

  def self.imap_connect
    @imap_mutex.synchronize do
      if keep_alive_thread.nil?
        start_keep_alive_thread
      end
      if @imap.nil? || @imap.disconnected?
        conf = account_config
        auth_type = conf[:imap_options][:auth_type] || "PLAIN"
        password = conf[:imap_options][:password]
        if auth_type == "gmail"
          auth_type = "XOAUTH2"
          password = google_access_token
        end
        Timeout.timeout(CONFIG[:mournmail_imap_connect_timeout]) do
          @imap = Net::IMAP.new(conf[:imap_host],
                                conf[:imap_options].except(:auth_type, :user_name, :password))
          @imap.authenticate(auth_type, conf[:imap_options][:user_name],
                             password)
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

  class GoogleAuthCallbackServer
    def initialize
      @servers = Socket.tcp_server_sockets("127.0.0.1", 0)
    end

    def port
      @servers.first.local_address.ip_port
    end

    def receive_code
      Socket.accept_loop(@servers) do |sock, addr|
        line = sock.gets
        query_string = line.slice(%r'\AGET [^?]*\?(.*) HTTP/1.1\r\n', 1)
        params = CGI.parse(query_string)
        code = params["code"][0]
        while line = sock.gets
          break if line == "\r\n"
        end
        sock.print("HTTP/1.1 200 OK\r\n")
        sock.print("Content-Type: text/plain\r\n")
        sock.print("\r\n")
        if code
          sock.print("Authenticated!")
        else
          sock.print("Authentication failed!")
        end
        return code
      ensure
        sock.close
      end
    ensure
      @servers.each(&:close)
    end
  end

  def self.google_access_token(account = current_account)
    auth_path = File.expand_path("cache/#{account}/google_auth.json",
                                 CONFIG[:mournmail_directory])
    FileUtils.mkdir_p(File.dirname(auth_path))
    store = Google::APIClient::FileStore.new(auth_path)
    storage = Google::APIClient::Storage.new(store)
    storage.authorize
    if storage.authorization.nil?
      conf = CONFIG[:mournmail_accounts][account]
      path = File.expand_path(conf[:client_secret_path])
      client_secrets = Google::APIClient::ClientSecrets.load(path)
      callback_server = GoogleAuthCallbackServer.new
      auth_client = client_secrets.to_authorization
      auth_client.update!(
        :scope => 'https://mail.google.com/',
        :redirect_uri => "http://127.0.0.1:#{callback_server.port}/"
      )
      auth_uri = auth_client.authorization_uri.to_s
      foreground! do
        begin
          Launchy.open(auth_uri)
        rescue Launchy::CommandNotFoundError
          show_google_auth_uri(auth_uri)
        end
      end
      auth_client.code = callback_server.receive_code
      auth_client.fetch_access_token!
      old_umask = File.umask(077)
      begin
        storage.write_credentials(auth_client)
      ensure
        File.umask(old_umask)
      end
    else
      auth_client = storage.authorization
    end
    auth_client.access_token
  end

  def self.show_google_auth_uri(auth_uri)
    buffer = Buffer.find_or_new("*message*",
                                undo_limit: 0, read_only: true)
    buffer.apply_mode(Mournmail::MessageMode)
    buffer.read_only_edit do
      buffer.clear
      buffer.insert(<<~EOF)
        Open the following URI in your browser and type obtained code:

        #{auth_uri}
      EOF
    end
    window = Mournmail.message_window
    window.buffer = buffer
    buffer
  end
  
  def self.fetch_summary(mailbox, all: false)
    if all
      summary = Mournmail::Summary.new(mailbox)
    else
      summary = Mournmail::Summary.load_or_new(mailbox)
    end
    imap_connect do |imap|
      imap.select(mailbox)
      uidvalidity = imap.responses["UIDVALIDITY"].last
      if uidvalidity && summary.uidvalidity &&
          uidvalidity != summary.uidvalidity
        clear = foreground! {
          yes_or_no?("UIDVALIDITY has been changed; Clear cache?")
        }
        if clear
          summary = Mournmail::Summary.new(mailbox)
        end
      end
      summary.uidvalidity = uidvalidity
      uids = imap.uid_search("ALL")
      new_uids = uids - summary.uids
      return summary if new_uids.empty?
      summary.synchronize do
        new_uids.each_slice(1000) do |uid_chunk|
          data = imap.uid_fetch(uid_chunk, ["UID", "ENVELOPE", "FLAGS"])
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
      end
      summary
    end
  rescue SocketError, Timeout::Error => e
    foreground do
      message(e.message)
    end
    summary
  end

  def self.show_summary(summary)
    buffer = Buffer.find_or_new("*summary*", undo_limit: 0,
                                read_only: true)
    buffer.apply_mode(Mournmail::SummaryMode)
    buffer.read_only_edit do
      buffer.clear
      buffer.insert(summary.to_s)
    end
    switch_to_buffer(buffer)
    Mournmail.current_mailbox = summary.mailbox
    Mournmail.current_summary = summary
    Mournmail.current_mail = nil
    Mournmail.current_uid = nil
    begin
      buffer.beginning_of_buffer
      buffer.re_search_forward(/^ *\d+ u/)
    rescue SearchError
      buffer.end_of_buffer
      buffer.re_search_backward(/^ *\d+ /, raise_error: false)
    end
    summary_read_command
  end

  def self.mailbox_cache_path(mailbox)
    File.expand_path("cache/#{current_account}/mailboxes/#{mailbox}",
                     CONFIG[:mournmail_directory])
  end

  def self.mail_cache_path(cache_id)
    dir = cache_id[0, 2]
    File.expand_path("cache/#{current_account}/mails/#{dir}/#{cache_id}",
                     CONFIG[:mournmail_directory])
  end

  def self.read_mail_cache(cache_id)
    path = Mournmail.mail_cache_path(cache_id)
    File.read(path)
  end

  def self.write_mail_cache(s)
    header = s.slice(/.*\r\n\r\n/m)
    cache_id = Digest::SHA256.hexdigest(header)
    path = mail_cache_path(cache_id)
    dir = File.dirname(path)
    base = File.basename(path)
    begin
      f = Tempfile.create(["#{base}-", ".tmp"], dir,
                          external_encoding: "ASCII-8BIT", binmode: true)
      begin
        f.write(s)
      ensure
        f.close
      end
    rescue Errno::ENOENT
      FileUtils.mkdir_p(File.dirname(path))
      retry
    end
    File.rename(f.path, path)
    cache_id
  end

  def self.index_mail(cache_id, mail)
    messages_db = Groonga["Messages"]
    unless messages_db.has_key?(cache_id)
      thread_id = find_thread_id(mail, messages_db)
      list_id = (mail["List-Id"] || mail["X-ML-Name"])
      messages_db.add(cache_id,
                      message_id: header_text(mail.message_id),
                      thread_id: header_text(thread_id),
                      date: mail.date&.to_time,
                      subject: header_text(mail.subject),
                      from: header_text(mail["From"]),
                      to: header_text(mail["To"]),
                      cc: header_text(mail["Cc"]),
                      list_id: header_text(list_id),
                      body: body_text(mail))
    end
  end

  class << self
    private

    def find_thread_id(mail, messages_db)
      references = Array(mail.references) | Array(mail.in_reply_to)
      if references.empty?
        mail.message_id
      elsif /\Aredmine\.issue-/.match?(references.first)
        references.first
      else
        parent = messages_db.select { |m|
          references.inject(nil) { |cond, ref|
            if cond.nil?
              m.message_id == ref
            else
              cond | (m.message_id == ref)
            end
          }
        }.first
        if parent
          parent.thread_id
        else
          mail.message_id
        end
      end
    end

    def header_text(s)
      force_utf8(s.to_s)
    end
    
    def body_text(mail)
      if mail.multipart?
        mail.parts.map { |part|
          part_text(part)
        }.join("\n")
      else
        s = mail.body.decoded
        to_utf8(s, mail.charset).gsub(/\r\n/, "\n")
      end
    rescue
      ""
    end
    
    def part_text(part)
      if part.multipart?
        part.parts.map { |part|
          part_text(part)
        }.join("\n")
      elsif part.main_type == "message" && part.sub_type == "rfc822"
        mail = Mail.new(part.body.raw_source)
        body_text(mail)
      elsif part.attachment?
        force_utf8(part.filename.to_s)
      else
        if part.main_type == "text" && part.sub_type == "plain"
          force_utf8(part.decoded).sub(/(?<!\n)\z/, "\n").gsub(/\r\n/, "\n")
        else
          ""
        end
      end
    rescue
      ""
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
    s.dup.force_encoding(Encoding::UTF_8).scrub("?")
  end

  def self.to_utf8(s, charset)
    if /\Autf-8\z/i.match?(charset)
      force_utf8(s)
    else
      begin
        s.encode(Encoding::UTF_8, charset, replace: "?")
      rescue
        force_utf8(NKF.nkf("-w", s))
      end
    end.gsub(/\r\n/, "\n")
  end

  def self.open_groonga_db
    db_path = File.expand_path("groonga/#{current_account}/messages.db",
                               CONFIG[:mournmail_directory])
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

  def self.parse_mail(s)
    Mail.new(s.scrub("??"))
  end

  def self.read_account_name(prompt, **opts)
    f = ->(s) {
      complete_for_minibuffer(s, CONFIG[:mournmail_accounts].keys)
    }
    read_from_minibuffer(prompt, completion_proc: f, **opts)
  end

  def self.insert_signature
    account = Buffer.current[:mournmail_delivery_account] ||
      Mournmail.current_account
    signature = CONFIG[:mournmail_accounts][account][:signature]
    if signature
      Buffer.current.save_excursion do
        end_of_buffer
        insert("\n")
        insert(signature)
      end
    end
  end
end
