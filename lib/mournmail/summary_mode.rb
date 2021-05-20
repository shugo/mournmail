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
    SUMMARY_MODE_MAP.define_key("o", :summary_refile_command)
    SUMMARY_MODE_MAP.define_key("!", :summary_refile_spam_command)
    SUMMARY_MODE_MAP.define_key("p", :summary_prefetch_command)
    SUMMARY_MODE_MAP.define_key("X", :summary_expunge_command)
    SUMMARY_MODE_MAP.define_key("v", :summary_view_source_command)
    SUMMARY_MODE_MAP.define_key("M", :summary_merge_partial_command)
    SUMMARY_MODE_MAP.define_key("q", :mournmail_quit)
    SUMMARY_MODE_MAP.define_key("k", :previous_line)
    SUMMARY_MODE_MAP.define_key("j", :next_line)
    SUMMARY_MODE_MAP.define_key("m", :mournmail_visit_mailbox)
    SUMMARY_MODE_MAP.define_key("S", :mournmail_visit_spam_mailbox)
    SUMMARY_MODE_MAP.define_key("/", :summary_search_command)
    SUMMARY_MODE_MAP.define_key("t", :summary_show_thread_command)
    SUMMARY_MODE_MAP.define_key("@", :summary_change_account_command)

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
      summary = Mournmail.current_summary
      Mournmail.background do
        mail, fetched = summary.read_mail(uid)
        foreground do
          show_message(mail)
          mark_as_seen(uid, false)
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
        mail = read_current_mail[0]
        body = mail.render_body
        foreground do
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
          references = mail.references ?
            Array(mail.references) : Array(mail.in_reply_to)
          if mail.message_id
            insert("\nIn-Reply-To: <#{mail.message_id}>")
            references.push(mail.message_id)
          end
          if !references.empty?
            refs = references.map { |id| "<#{id}>" }.join(" ")
            insert("\nReferences: " + refs)
          end
          end_of_buffer
          push_mark
          insert(<<~EOF + body.gsub(/^/, "> "))
        
        
        On #{mail['date']}
        #{mail['from']} wrote:
      EOF
          Mournmail.insert_signature
          exchange_point_and_mark
          run_hooks(:mournmail_draft_setup_hook)
        end
      end
    end

    define_local_command(:summary_forward,
                         doc: "Forward the current message.") do
      message = current_message
      Window.current = Mournmail.message_window
      Commands.mail
      re_search_forward(/^Subject: /)
      insert("Forward: " + message.subject)
      insert("\nAttached-Message: #{message._key}")
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
        Toggle Deleted.  Type `X` to expunge deleted messages.
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
      mailbox = Mournmail.current_mailbox
      summary = Mournmail.current_summary
      Mournmail.background do
        Mournmail.imap_connect do |imap|
          imap.expunge
        end
        summary.delete_item_if do |item|
          if item.flags.include?(:Deleted)
            if item.cache_id
              begin
                File.unlink(Mournmail.mail_cache_path(item.cache_id))
              rescue Errno::ENOENT
              end
              begin
                Groonga["Messages"].delete(item.cache_id)
              rescue Groonga::InvalidArgument
              end
              true
            end
          else
            false
          end
        end
        summary_text = summary.to_s
        summary.save
        foreground do
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
        mail, = read_current_mail
        foreground do
          source_buffer = Buffer.find_or_new("*message-source*",
                                             file_encoding: "ascii-8bit",
                                             undo_limit: 0, read_only: true)
          source_buffer.read_only_edit do
            source_buffer.clear
            source_buffer.insert(mail.raw_source.gsub(/\r\n/, "\n"))
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
      summary = Mournmail.current_summary
      Mournmail.background do
        id = nil
        total = nil
        mails = uids.map { |uid|
          summary.read_mail(uid)[0]
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
        foreground do
          show_message(mail)
          Mournmail.current_uid = nil
          Mournmail.current_mail = mail
        end
      end
    end

    define_local_command(:summary_archive,
                         doc: "Archive marked mails.") do
      archive_mailbox_format =
        Mournmail.account_config[:archive_mailbox_format]
      if archive_mailbox_format.nil?
        raise EditorError, "No archive_mailbox_format in the current account"
      end
      uids = marked_uids
      summary = Mournmail.current_summary
      now = Time.now
      if archive_mailbox_format == false
        mailboxes = { nil => uids }
      else
        mailboxes = uids.map { |uid| summary[uid] }.group_by { |item|
          t = Time.parse(item.date) rescue now
          t.strftime(archive_mailbox_format)
        }.transform_values { |items|
          items.map(&:uid)
        }
      end
      source_mailbox = Mournmail.current_mailbox
      if mailboxes.key?(source_mailbox)
        raise EditorError, "Can't archive mails in archive mailboxes"
      end
      Mournmail.background do
        Mournmail.imap_connect do |imap|
          mailboxes.each do |mailbox, item_uids|
            if mailbox && !imap.list("", mailbox)
              imap.create(mailbox)
            end
            refile_mails(imap, source_mailbox, item_uids, mailbox)
          end
          imap.expunge
          delete_from_summary(summary, uids, "Archived messages")
        end
      end
    end

    define_local_command(:summary_refile,
                         doc: "Refile marked mails.") do
      |mailbox = Mournmail.read_mailbox_name("Refile mails: ")|
      uids = marked_uids
      summary = Mournmail.current_summary
      source_mailbox = Mournmail.current_mailbox
      if source_mailbox == mailbox
        raise EditorError, "Can't refile to the same mailbox"
      end
      Mournmail.background do
        Mournmail.imap_connect do |imap|
          unless imap.list("", mailbox)
            if foreground! { yes_or_no?("#{mailbox} doesn't exist; Create?") }
              imap.create(mailbox)
            else
              next
            end
          end
          refile_mails(imap, source_mailbox, uids, mailbox)
          delete_from_summary(summary, uids, "Refiled messages")
        end
      end
    end

    define_local_command(:summary_refile_spam,
                         doc: "Refile marked mails as spam.") do
      mailbox = Mournmail.account_config[:spam_mailbox]
      if mailbox.nil?
        raise EditorError, "spam_mailbox is not specified"
      end
      summary_refile(Net::IMAP.encode_utf7(mailbox))
    end

    define_local_command(:summary_prefetch,
                         doc: "Prefetch mails.") do
      summary = Mournmail.current_summary
      mailbox = Mournmail.current_mailbox
      spam_mailbox = Mournmail.account_config[:spam_mailbox]
      if mailbox == Net::IMAP.encode_utf7(spam_mailbox)
        raise EditorError, "Can't prefetch spam"
      end
      target_uids = @buffer.to_s.scan(/^ *\d+/).map { |s|
        s.to_i
      }.select { |uid|
        summary[uid].cache_id.nil?
      }
      Mournmail.background do
        Mournmail.imap_connect do |imap|
          imap.select(mailbox)
          count = 0
          begin
            target_uids.each_slice(20) do |uids|
              data = imap.uid_fetch(uids, "BODY[]")
              data&.each do |i|
                uid = i.attr["UID"]
                s = i.attr["BODY[]"]
                if s
                  cache_id = Mournmail.write_mail_cache(s)
                  Mournmail.index_mail(cache_id, Mail.new(s))
                  summary[uid].cache_id = cache_id
                end
              end
              count += uids.size
              progress = (count.to_f * 100 / target_uids.size).round
              foreground do
                message("Prefetching mails... #{progress}%", log: false)
              end
            end
          ensure
            summary.save
          end
        end
        foreground do
          message("Done")
        end
      end
    end
    
    define_local_command(:summary_search, doc: "Search mails.") do
      |query = read_from_minibuffer("Search mail: ",
                                    initial_value: @buffer[:query]),
        page = 1|
      Mournmail.background do
        messages = Groonga["Messages"].select { |record|
          record.match(query) { |match_record|
            match_record.subject | match_record.body
          }
        }.paginate([["date", :desc]], page: page, size: 100)
        foreground do
          show_search_result(messages, query: query)
          message("Searched (#{messages.current_page}/#{messages.n_pages})")
        end
      end
    end

    define_local_command(:summary_show_thread,
                         doc: "Show the thread of the current mail.") do
      Mournmail.background do
        message = current_message
        messages = Groonga["Messages"].select { |m|
          m.thread_id == message.thread_id
        }.sort([["date", :asc]])
        foreground do
          show_search_result(messages, buffer_name: "*thread*")
          i = messages.find_index { |m| m._key == message._key }
          Buffer.current.goto_line(i + 1)
        end
      end
    end

    define_local_command(:summary_change_account,
                         doc: "Change the current account.") do
      |account = Mournmail.read_account_name("Change account: ")|
      unless CONFIG[:mournmail_accounts].key?(account)
        raise EditorError, "No such account: #{account}"
      end
      if Mournmail.background_thread
        raise EditorError, "Background thread is running"
      end
      mournmail_quit
      Mournmail.current_account = account
      mournmail
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
      summary = Mournmail.current_summary
      uid = selected_uid
      summary.read_mail(uid)
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
          foreground do
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

    def show_search_result(messages,
                           query: nil, buffer_name: "*search result*")
      summary_text = messages.map { |m|
        format("%s [ %s ] %s\n",
               m.date.strftime("%m/%d %H:%M"),
               ljust(m.from.to_s, 16),
               ljust(m.subject.to_s, 45))
      }.join
      buffer = Buffer.find_or_new(buffer_name, undo_limit: 0,
                                  read_only: true)
      buffer.apply_mode(Mournmail::SearchResultMode)
      buffer.read_only_edit do
        buffer.clear
        buffer.insert(summary_text)
        buffer.beginning_of_buffer
      end
      buffer[:messages] = messages
      buffer[:query] = query
      switch_to_buffer(buffer)
    end

    def ljust(s, n)
      width = 0
      str = +""
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

    def refile_mails(imap, src_mailbox, uids, dst_mailbox)
      count = 0
      uids.each_slice(100) do |uid_set|
        if dst_mailbox
          imap.uid_copy(uid_set, dst_mailbox) 
        end
        imap.uid_store(uid_set, "+FLAGS", [:Deleted])
        count += uid_set.size
        progress = (count.to_f * 100 / uids.size).round
        foreground do
          if dst_mailbox
            message("Refiling mails to #{dst_mailbox}... #{progress}%",
                    log: false)
          else
            message("Deleting mails... #{progress}%", log: false)
          end 
        end
      end
      foreground do
        if dst_mailbox
          message("Refiled mails to #{dst_mailbox}")
        else
          message("Deleted mails")
        end
      end
    end

    def current_message
      uid = selected_uid
      item = Mournmail.current_summary[uid]
      message = Groonga["Messages"][item.cache_id]
      if message.nil?
        raise EditorError, "No message found"
      end
      message
    end

    def delete_from_summary(summary, uids, msg)
      summary.delete_item_if do |item|
        uids.include?(item.uid)
      end
      summary_text = summary.to_s
      summary.save
      foreground do
        @buffer.read_only_edit do
          @buffer.clear
          @buffer.insert(summary_text)
        end
        message(msg)
      end
    end
  end
end
