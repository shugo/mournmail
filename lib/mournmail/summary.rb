require "time"
require "fileutils"
require "monitor"

module Mournmail
  class Summary
    attr_reader :mailbox, :items, :last_uid
    attr_accessor :uidvalidity

    include MonitorMixin

    LOCK_OPERATIONS = Hash.new(:unknown_mode)
    LOCK_OPERATIONS[:shared] = File::LOCK_SH
    LOCK_OPERATIONS[:exclusive] = File::LOCK_EX

    def self.lock_cache(mailbox, mode)
      File.open(Summary.cache_lock_path(mailbox), "w", 0600) do |f|
        f.flock(LOCK_OPERATIONS[mode])
        yield
      end
    end

    def self.cache_path(mailbox)
      File.join(Mournmail.mailbox_cache_path(mailbox), ".summary")
    end

    def self.cache_lock_path(mailbox)
      cache_path(mailbox) + ".lock"
    end

    def self.cache_tmp_path(mailbox)
      cache_path(mailbox) + ".tmp"
    end

    def self.cache_old_path(mailbox)
      cache_path(mailbox) + ".old"
    end

    def self.load(mailbox)
      lock_cache(mailbox, :shared) do
        File.open(cache_path(mailbox)) do |f|
          Marshal.load(f)
        end
      end
    end

    def self.load_or_new(mailbox)
      load(mailbox)
    rescue Errno::ENOENT
      new(mailbox)
    end

    def initialize(mailbox)
      super()
      @mailbox = mailbox
      @items = []
      @message_id_table = {}
      @uid_table = {}
      @last_uid = nil
      @uidvalidity = nil
    end

    DUMPABLE_VARIABLES = [
      :@mailbox,
      :@items,
      :@message_id_table,
      :@uid_table,
      :@last_uid,
      :@uidvalidity
    ]

    def marshal_dump
      DUMPABLE_VARIABLES.each_with_object({}) { |var, h|
        h[var] = instance_variable_get(var)
      }
    end

    def marshal_load(data)
      mon_initialize
      data.each do |var, val|
        instance_variable_set(var, val)
      end
    end

    def add_item(item, message_id, in_reply_to)
      synchronize do
# Disable threads
#        parent = @message_id_table[in_reply_to]
#        if parent
#          parent.add_reply(item)
#        else
#          @items.push(item)
#        end
        @items.push(item)
        if message_id
          @message_id_table[message_id] = item
        end
        @uid_table[item.uid] = item
        @last_uid = item.uid
      end
    end

    def delete_item_if(&block)
      synchronize do
        @items = @items.flat_map { |item|
          item.delete_reply_if(&block)
          if yield(item)
            item.replies
          else
            [item]
          end
        }
      end
    end

    def [](uid)
      synchronize do
        @uid_table[uid]
      end
    end

    def uids
      synchronize do
        @uid_table.keys
      end
    end

    def read_mail(uid)
      synchronize do
        item = @uid_table[uid]
        if item.cache_id
          File.open(Mournmail.mail_cache_path(item.cache_id)) do |f|
            [Mournmail.parse_mail(f.read), false]
          end
        else
          Mournmail.imap_connect do |imap|
            imap.select(@mailbox)
            data = imap.uid_fetch(uid, "BODY[]")
            if data.nil? || data.empty?
              raise EditorError, "No such mail: #{uid}"
            end
            s = data[0].attr["BODY[]"]
            mail = Mournmail.parse_mail(s)
            if @mailbox != Mournmail.account_config[:spam_mailbox]
              item.cache_id = Mournmail.write_mail_cache(s)
              Mournmail.index_mail(item.cache_id, mail)
            end
            [mail, true]
          end
        end
      end
    end

    def save
      synchronize do
        path = Summary.cache_path(@mailbox)
        FileUtils.mkdir_p(File.dirname(path))
        Summary.lock_cache(@mailbox, :exclusive) do
          cache_path = Summary.cache_path(@mailbox)
          tmp_path = Summary.cache_tmp_path(@mailbox)
          old_path = Summary.cache_old_path(@mailbox)
          File.open(tmp_path, "w", 0600) do |f|
            Marshal.dump(self, f)
          end
          File.rename(cache_path, old_path)
          File.rename(tmp_path, cache_path)
        end
      end
    end

    def to_s
      synchronize do
        items.each_with_object(+"") do |item, s|
          s << item.to_s
        end
      end
    end
  end
  
  class SummaryItem
    attr_reader :uid, :date, :from, :subject, :flags
    attr_reader :replies
    attr_accessor :cache_id
    
    def initialize(uid, date, from, subject, flags)
      @uid = uid
      @date = date
      @from = from
      @subject = subject
      @flags = flags
      @line = nil
      @replies = []
      @cache_id = nil
    end
    
    def add_reply(reply)
      @replies << reply
    end

    def delete_reply_if(&block)
      @replies = @replies.flat_map { |reply|
        reply.delete_reply_if(&block)
        if yield(reply)
          reply.replies
        else
          [reply]
        end
      }
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

    def set_flag(flag, update_server: true)
      if !@flags.include?(flag)
        update_flag("+", flag, update_server: update_server)
      end
    end

    def unset_flag(flag, update_server: true)
      if @flags.include?(flag)
        update_flag("-", flag, update_server: update_server)
      end
    end

    def toggle_flag(flag, update_server: true)
      sign = @flags.include?(flag) ? "-" : "+"
      update_flag(sign, flag, update_server: update_server)
    end

    def flags_char
      format_flags(@flags)
    end
    
    private

    def format_line(limit = 78, from_limit = 16, level = 0)
      space = "  " * (level < 8 ? level : 8)
      s = +""
      s << format("%6d %s%s %s[ %s ] ",
                  @uid, format_flags(@flags), format_date(@date), space,
                  ljust(format_from(@from), from_limit))
      s << ljust(decode_eword(@subject.to_s), limit - Buffer.display_width(s))
      s << "\n"
      s
    end
    
    def ljust(s, n)
      width = 0
      str = +""
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
      if !flags.include?(:Seen)
        "u"
      elsif flags.include?(:Deleted)
        "d"
      elsif flags.include?(:Flagged)
        "$"
      elsif flags.include?(:Answered)
        "a"
      else
        " "
      end
    end
    
    def format_date(date)
      (Time.parse(date) rescue Time.at(0)).localtime.strftime("%m/%d %H:%M")
    end
    
    def format_from(from)
      addr = from&.[](0)
      if addr.nil? || addr.mailbox.nil?
        return "Unknown sender"
      end
      mailbox = Mournmail.escape_binary(addr.mailbox)
      host = Mournmail.escape_binary(addr.host.to_s)
      if addr.name
        "#{decode_eword(addr.name)} <#{mailbox}@#{host}>"
      else
        "#{mailbox}@#{host}"
      end
    end 
    
    def decode_eword(s)
      Mournmail.decode_eword(s)
    end

    def update_flag(sign, flag, update_server: true)
      if update_server
        Mournmail.imap_connect do |imap|
          data = imap.uid_store(@uid, "#{sign}FLAGS", [flag])&.first
          if data
            @flags = data.attr["FLAGS"]
          else
            update_flag_local(sign, flag)
          end
        end
      else
        update_flag_local(sign, flag)
      end
      if @line
        s = format("%6d %s", @uid, format_flags(@flags))
        @line.sub!(/^ *\d+ ./, s)
      end
    end

    def update_flag_local(sign, flag)
      case sign
      when "+"
        @flags.push(flag)
      when "-"
        @flags.delete(flag)
      end
    end
  end
end
