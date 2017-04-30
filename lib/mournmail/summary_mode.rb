# frozen_string_literal: true

using Mournmail::MessageRendering

module Mournmail
  class SummaryMode < Textbringer::Mode
    SUMMARY_MODE_MAP = Keymap.new
    SUMMARY_MODE_MAP.define_key("s", :mournmail_summary_sync)
    SUMMARY_MODE_MAP.define_key(" ", :summary_read_command)
    SUMMARY_MODE_MAP.define_key(:backspace, :summary_scroll_down_command)
    SUMMARY_MODE_MAP.define_key("\C-h", :summary_scroll_down_command)
    SUMMARY_MODE_MAP.define_key("\C-?", :summary_scroll_down_command)
    SUMMARY_MODE_MAP.define_key("w", :summary_write_command)
    SUMMARY_MODE_MAP.define_key("a", :summary_reply_command)
    SUMMARY_MODE_MAP.define_key("A", :summary_reply_command)
    SUMMARY_MODE_MAP.define_key("f", :summary_forward_command)
    SUMMARY_MODE_MAP.define_key("u", :summary_toggle_seen_command)
    SUMMARY_MODE_MAP.define_key("$", :summary_toggle_flagged_command)
    SUMMARY_MODE_MAP.define_key("q", :mournmail_quit)
    SUMMARY_MODE_MAP.define_key("k", :previous_line)
    SUMMARY_MODE_MAP.define_key("j", :next_line)

    define_syntax :seen, /^\d+  .*/
    define_syntax :unseen, /^\d+ u.*/
    define_syntax :flagged, /^\d+ \$.*/

    def initialize(buffer)
      super(buffer)
      buffer.keymap = SUMMARY_MODE_MAP
    end

    define_local_command(:summary_read, doc: "Read a mail.") do
      uid = scroll_up_or_next_uid
      Mournmail.background do
        mailbox = Mournmail.current_mailbox
        mail = Mail.new(Mournmail.read_mail(mailbox, uid))
        message = mail.render
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
          mark_as_seen(uid)
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

    define_local_command(:summary_write,
                         doc: "Write a new mail.") do
      Window.current = Mournmail.message_window
      Commands.mail
    end

    define_local_command(:summary_reply,
                         doc: "Reply to the current message.") do
      |reply_all = current_prefix_arg|
      uid = selected_uid
      Mournmail.background do
        mailbox = Mournmail.current_mailbox
        mail = Mail.new(Mournmail.read_mail(mailbox, uid))
        body = mail.render_body
        next_tick do
          Window.current = Mournmail.message_window
          Commands.mail
          if reply_all
            insert(mail.from&.join(", "))
            cc_addrs = [mail.reply_to, mail.to, mail.cc].flat_map { |addrs|
              addrs || []
            }.uniq
            insert("\nCc: " + cc_addrs.join(", "))
          else
            insert(mail.reply_to&.join(", ") || mail.from&.join(", "))
          end
          re_search_forward(/^Subject: /)
          subject = mail["subject"].to_s
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

    private

    def selected_uid
      uid = @buffer.save_excursion {
        @buffer.beginning_of_line
        if !@buffer.looking_at?(/\d+/)
          raise EditorError, "No message found"
        end
        match_string(0).to_i
      }
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
        @buffer.end_of_line
        if @buffer.end_of_buffer?
          raise EditorError, "No more mail"
        end
        begin
          @buffer.re_search_forward(/^\d+ u/)
        rescue SearchError
          @buffer.forward_line
        end
        retry
      end
    end

    def mark_as_seen(uid)
      summary_item = Mournmail.current_summary[uid]
      if summary_item && !summary_item.flags.include?(:Seen)
        summary_item.set_flag(:Seen, update_server: false)
        Mournmail.current_summary.save
        update_flags(summary_item)
      end
    end

    def toggle_flag(uid, flag)
      summary_item = Mournmail.current_summary[uid]
      if summary_item
        summary_item.toggle_flag(flag)
        Mournmail.current_summary.save
        update_flags(summary_item)
      end
    end

    def update_flags(summary_item)
      @buffer.read_only_edit do
        @buffer.save_excursion do
          @buffer.beginning_of_buffer
          uid = summary_item.uid
          flags_char = summary_item.flags_char
          if @buffer.re_search_forward(/^#{uid} ./)
            @buffer.replace_match("#{uid} #{flags_char}")
          end
        end
      end
    end
  end
end
