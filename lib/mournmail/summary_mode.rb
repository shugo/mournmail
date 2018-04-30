# frozen_string_literal: true

require "tempfile"
require "digest"

using Mournmail::MessageRendering

module Mournmail
  class SummaryMode < Textbringer::Mode
    SUMMARY_MODE_MAP = Keymap.new
    SUMMARY_MODE_MAP.define_key("s", :mournmail_summary_sync)
    SUMMARY_MODE_MAP.define_key(" ", :summary_read_command)
    SUMMARY_MODE_MAP.define_key(:backspace, :summary_scroll_down_command)
    SUMMARY_MODE_MAP.define_key("\C-h", :summary_scroll_down_command)
    SUMMARY_MODE_MAP.define_key("\C-?", :summary_scroll_down_command)
    SUMMARY_MODE_MAP.define_key("n", :summary_next_command)
    SUMMARY_MODE_MAP.define_key("w", :summary_write_command)
    SUMMARY_MODE_MAP.define_key("a", :summary_reply_command)
    SUMMARY_MODE_MAP.define_key("A", :summary_reply_command)
    SUMMARY_MODE_MAP.define_key("f", :summary_forward_command)
    SUMMARY_MODE_MAP.define_key("u", :summary_toggle_seen_command)
    SUMMARY_MODE_MAP.define_key("$", :summary_toggle_flagged_command)
    SUMMARY_MODE_MAP.define_key("d", :summary_toggle_deleted_command)
    SUMMARY_MODE_MAP.define_key("x", :summary_toggle_mark_command)
    SUMMARY_MODE_MAP.define_key("*a", :summary_mark_all_command)
    SUMMARY_MODE_MAP.define_key("*n", :summary_unmark_all_command)
    SUMMARY_MODE_MAP.define_key("*r", :summary_mark_read_command)
    SUMMARY_MODE_MAP.define_key("*u", :summary_mark_unread_command)
    SUMMARY_MODE_MAP.define_key("*s", :summary_mark_flagged_command)
    SUMMARY_MODE_MAP.define_key("*t", :summary_mark_unflagged_command)
    SUMMARY_MODE_MAP.define_key("y", :summary_archive_command)
    SUMMARY_MODE_MAP.define_key("i", :summary_index_command)
    SUMMARY_MODE_MAP.define_key("X", :summary_expunge_command)
    SUMMARY_MODE_MAP.define_key("v", :summary_view_source_command)
    SUMMARY_MODE_MAP.define_key("M", :summary_merge_partial_command)
    SUMMARY_MODE_MAP.define_key("q", :mournmail_quit)
    SUMMARY_MODE_MAP.define_key("k", :previous_line)
    SUMMARY_MODE_MAP.define_key("j", :next_line)
    SUMMARY_MODE_MAP.define_key("m", :mournmail_visit_mailbox)
    SUMMARY_MODE_MAP.define_key("/", :summary_search_command)

    define_syntax :seen, /^ *\d+[ *] .*/
    define_syntax :unseen, /^ *\d+[ *]u.*/
    define_syntax :flagged, /^ *\d+[ *]\$.*/
    define_syntax :deleted, /^ *\d+[ *]d.*/
    define_syntax :answered, /^ *\d+[ *]a.*/

    def initialize(buffer)
      super(buffer)
      buffer.keymap = SUMMARY_MODE_MAP
    end

    define_local_command(:summary_read, doc: "Read a mail.") do
      uid = scroll_up_or_next_uid
      return if uid.nil?
      Mournmail.background do
        mailbox = Mournmail.current_mailbox
        s, fetched = Mournmail.read_mail(mailbox, uid)
        mail = Mail.new(s)
        if fetched
          index_mail(mailbox, uid, mail)
        end
        next_tick do
          show_message(mail)
          mark_as_seen(uid, !fetched)
          Mournmail.current_uid = uid
          Mournmail.current_mail = mail
        end
      end
    end

    define_local_command(:summary_scroll_down,
                         doc: "Scroll down the current message.") do
      uid = selected_uid
      if uid == Mournmail.current_uid
        window = Mournmail.message_window
        if window.buffer.name == "*message*"
          old_window = Window.current
          begin
            Window.current = window
            scroll_down
            return
          ensure
            Window.current = old_window
          end
        end
      end
    end

    define_local_command(:summary_next,
                         doc: "Display the next mail.") do
      next_message
      summary_read
    end

    define_local_command(:summary_write,
                         doc: "Write a new mail.") do
      Window.current = Mournmail.message_window
      Commands.mail
    end

    define_local_command(:summary_reply,
                         doc: "Reply to the current message.") do
      |reply_all = current_prefix_arg|
      Mournmail.background do
        mail = Mail.new(read_current_mail[0])
        body = mail.render_body
        next_tick do
          Window.current = Mournmail.message_window
          Commands.mail(run_hooks: false)
          if reply_all
            insert(mail.from&.join(", "))
            cc_addrs = [mail.reply_to, mail.to, mail.cc].flat_map { |addrs|
              addrs || []
            }.uniq.reject { |addr|
              mail.from&.include?(addr)
            }
            insert("\nCc: " + cc_addrs.join(", "))
          else
            insert(mail.reply_to&.join(", ") || mail.from&.join(", "))
          end
          re_search_forward(/^Subject: /)
          subject = mail["subject"].to_s.gsub(/\t/, " ")
          if /\Are:/i !~ subject
            insert("Re: ")
          end
          insert(subject)
          if mail['message-id']
            insert("\nIn-Reply-To: #{mail['message-id']}")
          end
          end_of_buffer
          push_mark
          insert(<<~EOF + body.gsub(/^/, "> "))
        
        
        On #{mail['date']}
        #{mail['from']} wrote:
      EOF
          exchange_point_and_mark
          run_hooks(:mournmail_draft_setup_hook)
        end
      end
    end

    define_local_command(:summary_forward,
                         doc: "Forward the current message.") do
      uid = selected_uid
      summary = Mournmail.current_summary
      item = summary[uid]
      Window.current = Mournmail.message_window
      Commands.mail
      re_search_forward(/^Subject: /)
      insert("Forward: " + Mournmail.decode_eword(item.subject))
      insert("\nAttached-Message: #{Mournmail.current_mailbox}/#{uid}")
      re_search_backward(/^To: /)
      end_of_line
    end

    define_local_command(:summary_toggle_seen,
                         doc: "Toggle Seen.") do
      toggle_flag(selected_uid, :Seen)
    end

    define_local_command(:summary_toggle_flagged,
                         doc: "Toggle Flagged.") do
      toggle_flag(selected_uid, :Flagged)
    end

    define_local_command(:summary_toggle_deleted,
                         doc: <<~EOD) do
        Toggle Deleted.  Type `x` to expunge deleted messages.
      EOD
      toggle_flag(selected_uid, :Deleted)
    end

    define_local_command(:summary_toggle_mark, doc: "Toggle mark.") do
      @buffer.read_only_edit do
        @buffer.save_excursion do
          @buffer.beginning_of_line
          if @buffer.looking_at?(/( *\d+)([ *])/)
            uid = @buffer.match_string(1)
            old_mark = @buffer.match_string(2)
            new_mark = old_mark == "*" ? " " : "*"
            @buffer.replace_match(uid + new_mark)
          end
        end
      end
    end

    define_local_command(:summary_mark_all, doc: "Mark all mails.") do
      gsub_buffer(/^( *\d+) /, '\\1*')
    end

    define_local_command(:summary_unmark_all, doc: "Unmark all mails.") do
      gsub_buffer(/^( *\d+)\*/, '\\1 ')
    end

    define_local_command(:summary_mark_read, doc: "Mark read mails.") do
      gsub_buffer(/^( *\d+) ([^u])/, '\\1*\\2')
    end

    define_local_command(:summary_mark_unread, doc: "Mark unread mails.") do
      gsub_buffer(/^( *\d+) u/, '\\1*u')
    end

    define_local_command(:summary_mark_flagged, doc: "Mark flagged mails.") do
      gsub_buffer(/^( *\d+) \$/, '\\1*$')
    end

    define_local_command(:summary_mark_unflagged,
                         doc: "Mark unflagged mails.") do
      gsub_buffer(/^( *\d+) ([^$])/, '\\1*\\2')
    end

    define_local_command(:summary_expunge,
                         doc: <<~EOD) do
        Expunge deleted messages.
      EOD
      buffer = Buffer.current
      Mournmail.background do
        Mournmail.imap_connect do |imap|
          imap.expunge
        end
        summary = Mournmail.current_summary
        summary.delete_item_if do |item|
          item.flags.include?(:Deleted)
        end
        summary_text = summary.to_s
        summary.save
        next_tick do
          buffer.read_only_edit do
            buffer.clear
            buffer.insert(summary_text)
          end
          message("Expunged messages")
        end
      end
    end

    define_local_command(:summary_view_source,
                         doc: "View source of a mail.") do
      uid = selected_uid
      Mournmail.background do
        source, = read_current_mail
        next_tick do
          source_buffer = Buffer.find_or_new("*message-source*",
                                             file_encoding: "ascii-8bit",
                                             undo_limit: 0, read_only: true)
          source_buffer.read_only_edit do
            source_buffer.clear
            source_buffer.insert(source.gsub(/\r\n/, "\n"))
            source_buffer.file_format = :dos
            source_buffer.beginning_of_buffer
          end
          window = Mournmail.message_window
          window.buffer = source_buffer
        end
      end
    end

    define_local_command(:summary_merge_partial,
                         doc: "Merge marked message/partial.") do
      uids = []
      @buffer.save_excursion do
        @buffer.beginning_of_buffer
        while @buffer.re_search_forward(/^( *\d+)\*/, raise_error: false)
          uid = @buffer.match_string(0).to_i
          # @buffer.replace_match(@buffer.match_string(0) + " ")
          uids.push(uid)
        end
      end
      Mournmail.background do
        mailbox = Mournmail.current_mailbox
        id = nil
        total = nil
        mails = uids.map { |uid|
          Mail.new(Mournmail.read_mail(mailbox, uid)[0])
        }.select { |mail|
          mail.main_type == "message" &&
            mail.sub_type == "partial" #&&
            (id ||= mail["Content-Type"].parameters["id"]) ==
            mail["Content-Type"].parameters["id"] &&
            (total ||= mail["Content-Type"].parameters["total"]&.to_i)
        }.sort_by { |mail|
          mail["Content-Type"].parameters["number"].to_i
        }
        if mails.length != total
          raise EditorError, "No enough messages (#{mails.length} of #{total})"
        end
        s = mails.map { |mail| mail.body.decoded }.join
        mail = Mail.new(s)
        next_tick do
          show_message(mail)
          Mournmail.current_uid = nil
          Mournmail.current_mail = mail
        end
      end
    end

    define_local_command(:summary_archive,
                         doc: "Archive marked mails.") do
      uids = marked_uids
      summary = Mournmail.current_summary
      now = Time.now
      mailboxes = uids.map { |uid| summary[uid] }.group_by { |item|
        t = Time.parse(item.date) rescue now
        t.strftime(CONFIG[:mournmail_archive_mailbox_format])
      }
      source_mailbox = Mournmail.current_mailbox
      if mailboxes.key?(source_mailbox)
        raise EditorError, "Can't archive mails in archive mailboxes"
      end
      Mournmail.background do
        Mournmail.imap_connect do |imap|
          count = 0
          mailboxes.each do |mailbox, items|
            unless imap.list("", mailbox)
              imap.create(mailbox)
            end
            items.each_slice(1000) do |item_set|
              uid_set = item_set.map(&:uid)
              imap.uid_copy(uid_set, mailbox)
              imap.uid_store(uid_set, "+FLAGS", [:Deleted])
              count += item_set.size
              progress = (count.to_f * 100 / uids.size).round
              next_tick do
                message("Archiving mails... #{progress}%")
              end
            end
          end
          imap.expunge
        end
        next_tick do
          mournmail_summary_sync(source_mailbox, true)
          message("Done")
        end
      end
    end

    define_local_command(:summary_index,
                         doc: "Index marked mails.") do
      uids = marked_uids
      summary = Mournmail.current_summary
      mailbox = Mournmail.current_mailbox
      Mournmail.background do
        progress = 0
        uids.each_with_index do |uid, i|
          mail = Mail.new(Mournmail.read_mail(mailbox, uid)[0])
          index_mail(mailbox, uid, mail)
          new_progress = ((i + 1) * 100.0 / uids.length).floor
          if new_progress == 100 || new_progress - progress >= 10
            progress = new_progress
            next_tick do
              message("Indexing mails... #{progress}%")
            end
          end
        end
        next_tick do
          message("Done")
        end
      end
    end
    
    define_local_command(:summary_search) do
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

    private

    def selected_uid
      uid = @buffer.save_excursion {
        @buffer.beginning_of_line
        if !@buffer.looking_at?(/ *\d+/)
          Mournmail.current_mail = nil
          Mournmail.current_uid = nil
          raise EditorError, "No message found"
        end
        @buffer.match_string(0).to_i
      }
    end

    def marked_uids
      @buffer.to_s.scan(/^ *\d+(?=\*)/).map(&:to_i)
    end

    def read_current_mail
      mailbox = Mournmail.current_mailbox
      uid = selected_uid
      Mournmail.read_mail(mailbox, uid)
    end

    def scroll_up_or_next_uid
      begin
        uid = selected_uid
        if uid == Mournmail.current_uid
          window = Mournmail.message_window
          if window.buffer.name == "*message*"
            old_window = Window.current
            begin
              Window.current = window
              scroll_up
              return nil
            ensure
              Window.current = old_window
            end
          end
        end
        uid
      rescue RangeError # may be raised by scroll_up
        next_message
        retry
      end
    end

    def show_message(mail)
      message_buffer = Buffer.find_or_new("*message*",
                                          undo_limit: 0, read_only: true)
      message_buffer.apply_mode(Mournmail::MessageMode)
      message_buffer.read_only_edit do
        message_buffer.clear
        message_buffer.insert(mail.render)
        message_buffer.beginning_of_buffer
      end
      message_buffer[:mournmail_mail] = mail
      window = Mournmail.message_window
      window.buffer = message_buffer
    end
        
    def mark_as_seen(uid, update_server)
      summary_item = Mournmail.current_summary[uid]
      if summary_item && !summary_item.flags.include?(:Seen)
        summary_item.set_flag(:Seen, update_server: update_server)
        Mournmail.current_summary.save
        update_flags(summary_item)
      end
    end

    def toggle_flag(uid, flag)
      summary_item = Mournmail.current_summary[uid]
      if summary_item
        Mournmail.background do
          summary_item.toggle_flag(flag)
          Mournmail.current_summary.save
          next_tick do
            update_flags(summary_item)
          end
        end
      end
    end

    def update_flags(summary_item)
      @buffer.read_only_edit do
        @buffer.save_excursion do
          @buffer.beginning_of_buffer
          uid = summary_item.uid
          flags_char = summary_item.flags_char
          if @buffer.re_search_forward(/^( *#{uid}) ./)
            @buffer.replace_match(@buffer.match_string(1) + " " + flags_char)
          end
        end
      end
    end

    def next_message
      @buffer.end_of_line
      if @buffer.end_of_buffer?
        raise EditorError, "No more mail"
      end
      begin
        @buffer.re_search_forward(/^ *\d+ u/)
      rescue SearchError
        @buffer.forward_line
      end
    end

    def gsub_buffer(re, s)
      @buffer.read_only_edit do
        s = @buffer.to_s.gsub(re, s)
        @buffer.replace(s)
      end
    end

    def find_thread_id(mail, messages_db)
      references = Array(mail.references) | Array(mail.in_reply_to)
      if references.empty?
        mail.message_id
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
      s.to_s.scrub("?")
    end
    
    def body_text(mail)
      if mail.multipart?
        mail.parts.map { |part|
          part_text(part)
        }.join("\n")
      else
        s = mail.body.decoded
        Mournmail.to_utf8(s, mail.charset).gsub(/\r\n/, "\n")
      end
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
        ""
      else
        if part.main_type == "text" && part.sub_type == "plain"
          part.decoded.sub(/(?<!\n)\z/, "\n").gsub(/\r\n/, "\n")
        else
          ""
        end
      end
    end

    def index_mail(mailbox, uid, mail)
      messages_db = Groonga["Messages"]
      id = mail.message_id.to_s + "_" +
        Digest::SHA256.hexdigest(mail.header.to_s)
      unless messages_db.has_key?(id)
        thread_id = find_thread_id(mail, messages_db)
        mail_path = File.join(Mournmail.mailbox_cache_path(mailbox),
                              uid.to_s)
        list_id = (mail["List-Id"] || mail["X-ML-Name"])
        messages_db.add(id,
                        path: mail_path,
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
  end
end
