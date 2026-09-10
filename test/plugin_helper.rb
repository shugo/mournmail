# Shared setup for tests that need the whole plugin: Textbringer's globals,
# a throwaway CONFIG[:mournmail_directory] and, on demand, a real Groonga
# database.  These tests are omitted when Groonga cannot be loaded.

require "test/unit"
require "tmpdir"
require "fileutils"
require "securerandom"

begin
  require "groonga"
  MOURNMAIL_GROONGA_AVAILABLE = true
rescue LoadError
  MOURNMAIL_GROONGA_AVAILABLE = false
end

if MOURNMAIL_GROONGA_AVAILABLE
  require "curses"

  # Face.define calls Curses.init_pair, which opens the terminal and
  # aborts the process when there is none (TERM is unset on CI).  Stub
  # the screen-level functions the way Textbringer's own tests do.
  class << Curses
    [
      :init_screen, :close_screen,
      :echo, :noecho,
      :raw, :noraw,
      :nl, :nonl,
      :start_color,
      :use_default_colors,
      :init_pair,
      :doupdate
    ].each do |name|
      undef_method name
      define_method(name) { |*args| }
    end

    undef lines
    def lines
      24
    end

    undef cols
    def cols
      80
    end

    undef has_colors?
    def has_colors?
      true
    end

    undef color_pair
    def color_pair(n)
      0
    end

    undef colors
    def colors
      256
    end
  end

  require "textbringer"
  include Textbringer
  include Textbringer::Commands
  require "mournmail"
end

module Mournmail
  class PluginTestCase < Test::Unit::TestCase
    def setup
      unless MOURNMAIL_GROONGA_AVAILABLE
        omit("Groonga is not available")
      end
      @tmpdir = Dir.mktmpdir("mournmail-test")
      @saved_config = CONFIG.dup
      @saved_tz = ENV["TZ"]
      # format_date prints the local time.
      ENV["TZ"] = "UTC"
      CONFIG[:mournmail_directory] = @tmpdir
      CONFIG[:mournmail_accounts] = {
        "test" => {
          from: "Test User <test@example.com>",
          spam_mailbox: "Junk",
          delivery_method: :test,
          delivery_options: {}
        }
      }
      Mournmail.current_account = "test"
      # foreground { } only queues the block; nothing runs it.
      Controller.current = Controller.new
    end

    def teardown
      return unless MOURNMAIL_GROONGA_AVAILABLE
      Mournmail.close_groonga_db
      Mournmail.instance_variable_set(:@groonga_db, nil)
      Controller.current&.close
      Controller.current = nil
      Mournmail.current_summary = nil
      Mournmail.current_mailbox = nil
      Mournmail.current_uid = nil
      Mournmail.current_mail = nil
      ENV["TZ"] = @saved_tz
      CONFIG.replace(@saved_config)
      FileUtils.rm_rf(@tmpdir)
    end

    # A raw message with CRLF line endings, as IMAP returns it.  Header
    # names are given as keywords: message_id: becomes Message-Id.
    def raw_mail(body: "body\r\n", **headers)
      fields = {
        from: "Alice <alice@example.com>",
        to: "bob@example.com",
        subject: "hello",
        date: "Mon, 1 Sep 2025 10:00:00 +0000",
        message_id: "<#{SecureRandom.hex(8)}@example.com>"
      }.merge(headers)
      fields.filter_map { |name, value|
        next if value.nil?
        "#{name.to_s.split("_").map(&:capitalize).join("-")}: #{value}\r\n"
      }.join + "\r\n" + body
    end

    def with_groonga
      Mournmail.open_groonga_db
    end

    # Run the block with Mournmail.imap_connect yielding imap instead of a
    # real connection.  With nil, any attempt to connect raises.
    def with_imap(imap)
      Mournmail.singleton_class.class_eval do
        alias_method :imap_connect_without_fake, :imap_connect
        define_method(:imap_connect) do |&block|
          if imap.nil?
            raise "imap_connect must not be called in this test"
          end
          block.call(imap)
        end
      end
      yield
    ensure
      Mournmail.singleton_class.class_eval do
        alias_method :imap_connect, :imap_connect_without_fake
        remove_method :imap_connect_without_fake
      end
    end
  end
end
