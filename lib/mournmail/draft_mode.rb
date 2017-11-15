# frozen_string_literal: true

module Mournmail
  class DraftMode < Textbringer::Mode
    MAIL_MODE_MAP = Keymap.new
    MAIL_MODE_MAP.define_key("\C-c\C-c", :draft_send_command)
    MAIL_MODE_MAP.define_key("\C-c\C-k", :draft_kill_command)
    MAIL_MODE_MAP.define_key("\C-c\C-x\C-i", :draft_attach_file_command)
    MAIL_MODE_MAP.define_key("\t", :draft_complete_or_insert_tab_command)

    define_syntax :field_name, /^[A-Za-z\-]+: /
    define_syntax :quotation, /^>.*/
    define_syntax :header_end, /^--text follows this line--$/

    def initialize(buffer)
      super(buffer)
      buffer.keymap = MAIL_MODE_MAP
    end

    define_local_command(:draft_send,
                         doc: "Send a mail and exit from mail buffer.") do
      unless y_or_n?("Send this mail?")
        return
      end
      s = @buffer.to_s
      charset = CONFIG[:mournmail_charset]
      begin
        s.encode(charset)
      rescue Encoding::UndefinedConversionError
        charset = "utf-8"
      end
      m = Mail.new(charset: charset)
      m.transport_encoding = "8bit"
      header, body = s.split(/^--text follows this line--\n/, 2)
      attached_files = []
      attached_messages = []
      header.scan(/^([!-9;-~]+):[ \t]*(.*(?:\n[ \t].*)*)\n/) do |name, val|
        case name
        when "Attached-File"
          attached_files.push(val.strip)
        when "Attached-Message"
          attached_messages.push(val.strip)
        else
          m[name] = val
        end
      end
      if body.empty?
        return if !yes_or_no?("Body is empty.  Really send?")
      else
        if attached_files.empty? && attached_messages.empty?
          m.body = body
        else
          part = Mail::Part.new(content_type: "text/plain", body: body)
          part.charset = charset
          m.body << part
        end
      end
      attached_files.each do |file|
        m.add_file(file)
      end
      m.delivery_method(CONFIG[:mournmail_delivery_method],
                        CONFIG[:mournmail_delivery_options])
      bury_buffer(@buffer)
      background do
        begin
          if !attached_messages.empty?
            attached_messages.each do |attached_message|
              mailbox, uid = attached_message.strip.split("/")
              s, = Mournmail.read_mail(mailbox, uid.to_i)
              part = Mail::Part.new(content_type: "message/rfc822", body: s)
              m.body << part
            end
          end
          m.deliver!
          next_tick do
            message("Mail sent.")
          end
          outbox = CONFIG[:mournmail_outbox]
          if outbox
            Mournmail.imap_connect do |imap|
              imap.append(outbox, m.to_s, [:Seen])
            end
          end
          next_tick do
            kill_buffer(@buffer, force: true)
            Mournmail.back_to_summary
          end
        rescue Exception
          next_tick do
            switch_to_buffer(@buffer)
          end
          raise
        end
      end
    end
    
    define_local_command(:draft_kill, doc: "Kill the draft buffer.") do
      if yes_or_no?("Kill current draft?")
        kill_buffer(@buffer, force: true)
        Mournmail.back_to_summary
      end
    end
    
    define_local_command(:draft_attach_file, doc: "Attach a file.") do
      |file_name = read_file_name("Attach file: ")|
      @buffer.save_excursion do
        @buffer.beginning_of_buffer
        @buffer.re_search_forward(/^--text follows this line--$/)
        @buffer.beginning_of_line
        @buffer.insert("Attached-File: #{file_name}\n")
      end
    end
    
    define_local_command(:draft_complete_or_insert_tab,
                         doc: "Complete a mail address or insert a tab.") do
      is_address_field = @buffer.save_excursion {
        @buffer.beginning_of_line
        @buffer.looking_at?(/(To|Cc|Bcc):/i)
      }
      if is_address_field
        end_pos = @buffer.point
        @buffer.skip_re_backward(/[^ :,]/)
        start_pos = @buffer.point
        s = @buffer.substring(start_pos, end_pos)
        if !s.empty?
          re = /^(.*")?#{Regexp.quote(s)}.*/
          line = File.read(CONFIG[:mournmail_addresses_path]).slice(re)
          if line
            addr = line.slice(/^\S+/)
            @buffer.delete_region(start_pos, end_pos)
            @buffer.insert(addr)
          else
            @buffer.goto_char(end_pos)
            message("No match")
          end
        end
      else
        @buffer.insert("\t")
      end
    end
  end
end
