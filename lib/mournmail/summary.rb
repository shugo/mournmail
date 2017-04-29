# frozen_string_literal: true

require "time"
require "fileutils"

module Mournmail
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
      File.open(Summary.cache_path(@mailbox), "w", 0600) do |f|
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
      (Time.parse(date) rescue Time.at(0)).localtime.strftime("%m/%d %H:%M")
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
      Mournmail.decode_eword(s)
    end
  end
end
